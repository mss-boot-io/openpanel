package service

import (
	"crypto/md5"
	"crypto/tls"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/1Panel-dev/1Panel/core/app/dto"
	"github.com/1Panel-dev/1Panel/core/app/model"
	"github.com/1Panel-dev/1Panel/core/app/repo"
	"github.com/1Panel-dev/1Panel/core/constant"
	"github.com/1Panel-dev/1Panel/core/global"
	"github.com/1Panel-dev/1Panel/core/utils/encrypt"
	"github.com/gin-gonic/gin"
)

const OpenNodePrefix = "open:"

type OpenNodeService struct{}

type IOpenNodeService interface {
	Search(req dto.OpenNodeSearch) (int64, []dto.OpenNodeInfo, error)
	ListOptions() ([]dto.OpenNodeOption, error)
	Create(req dto.OpenNodeCreate) error
	Update(req dto.OpenNodeUpdate) error
	Delete(id uint) error
	Test(req dto.OpenNodeTest) (*dto.OpenNodeInfo, error)
	Proxy(c *gin.Context, currentNode string) error
}

func NewIOpenNodeService() IOpenNodeService {
	return &OpenNodeService{}
}

func IsOpenNodeName(currentNode string) bool {
	currentNode = strings.TrimSpace(currentNode)
	if strings.HasPrefix(currentNode, OpenNodePrefix) {
		return true
	}
	if currentNode == "" || currentNode == "local" {
		return false
	}
	node, err := openNodeRepo.Get(repo.WithByName(currentNode))
	return err == nil && node.ID != 0
}

func (u *OpenNodeService) Search(req dto.OpenNodeSearch) (int64, []dto.OpenNodeInfo, error) {
	options := []global.DBOption{
		repo.WithOrderDesc("created_at"),
		openNodeRepo.WithByInfo(req.Info),
	}
	total, nodes, err := openNodeRepo.Page(req.Page, req.PageSize, options...)
	if err != nil {
		return 0, nil, err
	}
	items := make([]dto.OpenNodeInfo, 0, len(nodes))
	for _, node := range nodes {
		items = append(items, openNodeDTO(node))
	}
	return total, items, nil
}

func (u *OpenNodeService) ListOptions() ([]dto.OpenNodeOption, error) {
	nodes, err := openNodeRepo.List(repo.WithOrderDesc("created_at"))
	if err != nil {
		return nil, err
	}
	version, _ := settingRepo.GetValueByKey("SystemVersion")
	options := []dto.OpenNodeOption{
		{
			ID:      0,
			Name:    "local",
			Addr:    "127.0.0.1",
			Value:   "local",
			Status:  constant.StatusHealthy,
			Version: version,
			IsBound: true,
		},
	}
	for _, node := range nodes {
		status := constant.StatusUnhealthy
		if node.Status == constant.StatusSuccess {
			status = constant.StatusHealthy
		}
		options = append(options, dto.OpenNodeOption{
			ID:      node.ID,
			Name:    node.Name,
			Addr:    node.BaseURL,
			Value:   fmt.Sprintf("%s%d", OpenNodePrefix, node.ID),
			Status:  status,
			Version: version,
			IsBound: true,
			Message: node.Message,
		})
	}
	return options, nil
}

func (u *OpenNodeService) Create(req dto.OpenNodeCreate) error {
	baseURL, err := normalizeOpenNodeURL(req.BaseURL)
	if err != nil {
		return err
	}
	if old, _ := openNodeRepo.Get(repo.WithByName(req.Name)); old.ID != 0 {
		return fmt.Errorf("open node %s already exists", req.Name)
	}
	apiKey, err := encrypt.StringEncrypt(strings.TrimSpace(req.APIKey))
	if err != nil {
		return err
	}
	node := model.OpenNode{
		Name:          strings.TrimSpace(req.Name),
		BaseURL:       baseURL,
		APIKey:        apiKey,
		SkipTLSVerify: req.SkipTLSVerify,
		Status:        constant.StatusFailed,
		Description:   req.Description,
	}
	return openNodeRepo.Create(&node)
}

func (u *OpenNodeService) Update(req dto.OpenNodeUpdate) error {
	node, err := openNodeRepo.Get(repo.WithByID(req.ID))
	if err != nil || node.ID == 0 {
		return errors.New("open node not found")
	}
	name := strings.TrimSpace(req.Name)
	if name != node.Name {
		if old, _ := openNodeRepo.Get(repo.WithByName(name)); old.ID != 0 {
			return fmt.Errorf("open node %s already exists", name)
		}
	}
	baseURL, err := normalizeOpenNodeURL(req.BaseURL)
	if err != nil {
		return err
	}
	updates := map[string]interface{}{
		"name":            name,
		"base_url":        baseURL,
		"skip_tls_verify": req.SkipTLSVerify,
		"description":     req.Description,
	}
	if strings.TrimSpace(req.APIKey) != "" {
		apiKey, err := encrypt.StringEncrypt(strings.TrimSpace(req.APIKey))
		if err != nil {
			return err
		}
		updates["api_key"] = apiKey
	}
	return openNodeRepo.Update(req.ID, updates)
}

func (u *OpenNodeService) Delete(id uint) error {
	node, err := openNodeRepo.Get(repo.WithByID(id))
	if err != nil || node.ID == 0 {
		return errors.New("open node not found")
	}
	return openNodeRepo.Delete(repo.WithByID(id))
}

func (u *OpenNodeService) Test(req dto.OpenNodeTest) (*dto.OpenNodeInfo, error) {
	node, err := u.loadNodeForTest(req)
	if err != nil {
		return nil, err
	}
	status, message := constant.StatusSuccess, ""
	if err := checkOpenNodeHealth(node); err != nil {
		status = constant.StatusFailed
		message = err.Error()
	}
	now := time.Now()
	if node.ID != 0 {
		_ = openNodeRepo.Update(node.ID, map[string]interface{}{
			"status":        status,
			"message":       message,
			"last_check_at": &now,
		})
		node.Status = status
		node.Message = message
		node.LastCheckAt = &now
	}
	info := openNodeDTO(node)
	if status != constant.StatusSuccess {
		return &info, errors.New(message)
	}
	return &info, nil
}

func (u *OpenNodeService) Proxy(c *gin.Context, currentNode string) error {
	nodeID, err := parseOpenNodeID(currentNode)
	if err != nil {
		return err
	}
	node, err := openNodeRepo.Get(repo.WithByID(nodeID))
	if err != nil || node.ID == 0 {
		return errors.New("open node not found")
	}
	apiKey, err := encrypt.StringDecrypt(node.APIKey)
	if err != nil {
		return err
	}
	target, err := url.Parse(node.BaseURL)
	if err != nil {
		return err
	}
	proxy := &httputil.ReverseProxy{
		Director: func(req *http.Request) {
			req.URL.Scheme = target.Scheme
			req.URL.Host = target.Host
			req.URL.Path = singleJoiningSlash(target.Path, req.URL.Path)
			req.URL.RawPath = ""
			req.URL.RawQuery = openNodeProxyQuery(target.RawQuery, req.URL.RawQuery)
			req.Host = target.Host
			req.Header.Set("CurrentNode", "local")
			req.Header.Del("Cookie")
			req.Header.Del(constant.CSRFHeaderName)
			req.Header.Del("Forwarded")
			req.Header.Del("X-Real-IP")
			req.Header["X-Forwarded-For"] = nil
			setOpenNodeAuthHeaders(req.Header, apiKey)
			if req.Header.Get("X-Forwarded-Proto") == "" {
				req.Header.Set("X-Forwarded-Proto", c.Request.URL.Scheme)
			}
			if req.Header.Get("X-Forwarded-Host") == "" && c.Request.Host != "" {
				req.Header.Set("X-Forwarded-Host", c.Request.Host)
			}
		},
		Transport: openNodeTransport(node.SkipTLSVerify),
		ErrorHandler: func(rw http.ResponseWriter, req *http.Request, err error) {
			rw.WriteHeader(http.StatusBadGateway)
			_, _ = rw.Write([]byte("Bad Gateway: " + err.Error()))
		},
	}
	proxy.ServeHTTP(c.Writer, c.Request)
	c.Abort()
	return nil
}

func (u *OpenNodeService) loadNodeForTest(req dto.OpenNodeTest) (model.OpenNode, error) {
	if req.ID != 0 {
		node, err := openNodeRepo.Get(repo.WithByID(req.ID))
		if err != nil || node.ID == 0 {
			return node, errors.New("open node not found")
		}
		if strings.TrimSpace(req.BaseURL) != "" {
			baseURL, err := normalizeOpenNodeURL(req.BaseURL)
			if err != nil {
				return node, err
			}
			node.BaseURL = baseURL
		}
		node.SkipTLSVerify = req.SkipTLSVerify
		if strings.TrimSpace(req.APIKey) != "" {
			apiKey, err := encrypt.StringEncrypt(strings.TrimSpace(req.APIKey))
			if err != nil {
				return node, err
			}
			node.APIKey = apiKey
		}
		return node, nil
	}
	baseURL, err := normalizeOpenNodeURL(req.BaseURL)
	if err != nil {
		return model.OpenNode{}, err
	}
	if strings.TrimSpace(req.APIKey) == "" {
		return model.OpenNode{}, errors.New("api key is required")
	}
	apiKey, err := encrypt.StringEncrypt(strings.TrimSpace(req.APIKey))
	if err != nil {
		return model.OpenNode{}, err
	}
	return model.OpenNode{
		BaseURL:       baseURL,
		APIKey:        apiKey,
		SkipTLSVerify: req.SkipTLSVerify,
	}, nil
}

func openNodeDTO(node model.OpenNode) dto.OpenNodeInfo {
	return dto.OpenNodeInfo{
		ID:            node.ID,
		Name:          node.Name,
		BaseURL:       node.BaseURL,
		SkipTLSVerify: node.SkipTLSVerify,
		Status:        node.Status,
		Message:       node.Message,
		LastCheckAt:   node.LastCheckAt,
		Description:   node.Description,
		CreatedAt:     node.CreatedAt,
		UpdatedAt:     node.UpdatedAt,
	}
}

func normalizeOpenNodeURL(raw string) (string, error) {
	raw = strings.TrimRight(strings.TrimSpace(raw), "/")
	if raw == "" {
		return "", errors.New("base url is required")
	}
	parsed, err := url.Parse(raw)
	if err != nil {
		return "", err
	}
	if parsed.Scheme != "http" && parsed.Scheme != "https" {
		return "", errors.New("base url scheme must be http or https")
	}
	if parsed.Host == "" {
		return "", errors.New("base url host is required")
	}
	parsed.RawQuery = ""
	parsed.Fragment = ""
	return parsed.String(), nil
}

func parseOpenNodeID(currentNode string) (uint, error) {
	currentNode = strings.TrimSpace(currentNode)
	if strings.HasPrefix(currentNode, OpenNodePrefix) {
		idText := strings.TrimPrefix(currentNode, OpenNodePrefix)
		id, err := strconv.ParseUint(idText, 10, 64)
		if err != nil || id == 0 {
			return 0, fmt.Errorf("invalid open node %s", currentNode)
		}
		return uint(id), nil
	}
	node, err := openNodeRepo.Get(repo.WithByName(currentNode))
	if err != nil || node.ID == 0 {
		return 0, fmt.Errorf("invalid open node %s", currentNode)
	}
	return node.ID, nil
}

func checkOpenNodeHealth(node model.OpenNode) error {
	apiKey, err := encrypt.StringDecrypt(node.APIKey)
	if err != nil {
		return err
	}
	req, err := http.NewRequest(http.MethodGet, node.BaseURL+"/api/v2/core/settings/search/available", nil)
	if err != nil {
		return err
	}
	setOpenNodeAuthHeaders(req.Header, apiKey)
	req.Header.Set("CurrentNode", "local")
	resp, err := (&http.Client{
		Transport: openNodeTransport(node.SkipTLSVerify),
		Timeout:   10 * time.Second,
	}).Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		return fmt.Errorf("remote status %s", resp.Status)
	}
	var response dto.Response
	if err := json.NewDecoder(resp.Body).Decode(&response); err != nil {
		return err
	}
	if response.Code != http.StatusOK {
		return fmt.Errorf("remote response code %d: %s", response.Code, response.Message)
	}
	return nil
}

func openNodeTransport(skipTLSVerify bool) *http.Transport {
	return &http.Transport{
		TLSClientConfig: &tls.Config{InsecureSkipVerify: skipTLSVerify},
		DialContext: (&net.Dialer{
			Timeout:   30 * time.Second,
			KeepAlive: 30 * time.Second,
		}).DialContext,
		TLSHandshakeTimeout:   10 * time.Second,
		ResponseHeaderTimeout: 60 * time.Second,
		IdleConnTimeout:       90 * time.Second,
		MaxIdleConns:          100,
		MaxIdleConnsPerHost:   20,
	}
}

func setOpenNodeAuthHeaders(header http.Header, apiKey string) {
	timestamp := strconv.FormatInt(time.Now().Unix(), 10)
	header.Set("1Panel-Timestamp", timestamp)
	header.Set("1Panel-Token", openNodeMD5("1panel"+apiKey+timestamp))
}

func openNodeMD5(text string) string {
	hash := md5.New()
	_, _ = hash.Write([]byte(text))
	return hex.EncodeToString(hash.Sum(nil))
}

func openNodeProxyQuery(targetQuery, requestQuery string) string {
	query, _ := url.ParseQuery(requestQuery)
	query.Del("operateNode")
	if targetQuery != "" {
		targetValues, _ := url.ParseQuery(targetQuery)
		for key, values := range targetValues {
			for _, value := range values {
				query.Add(key, value)
			}
		}
	}
	return query.Encode()
}

func singleJoiningSlash(a, b string) string {
	aslash := strings.HasSuffix(a, "/")
	bslash := strings.HasPrefix(b, "/")
	switch {
	case aslash && bslash:
		return a + b[1:]
	case !aslash && !bslash:
		return a + "/" + b
	default:
		return a + b
	}
}
