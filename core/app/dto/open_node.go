package dto

import "time"

type OpenNodeCreate struct {
	Name          string `json:"name" validate:"required"`
	BaseURL       string `json:"baseUrl" validate:"required"`
	APIKey        string `json:"apiKey" validate:"required"`
	SkipTLSVerify bool   `json:"skipTLSVerify"`
	Description   string `json:"description"`
}

type OpenNodeUpdate struct {
	ID            uint   `json:"id" validate:"required"`
	Name          string `json:"name" validate:"required"`
	BaseURL       string `json:"baseUrl" validate:"required"`
	APIKey        string `json:"apiKey"`
	SkipTLSVerify bool   `json:"skipTLSVerify"`
	Description   string `json:"description"`
}

type OpenNodeSearch struct {
	PageInfo
	Info string `json:"info"`
}

type OpenNodeTest struct {
	ID            uint   `json:"id"`
	BaseURL       string `json:"baseUrl"`
	APIKey        string `json:"apiKey"`
	SkipTLSVerify bool   `json:"skipTLSVerify"`
}

type OpenNodeInfo struct {
	ID            uint       `json:"id"`
	Name          string     `json:"name"`
	BaseURL       string     `json:"baseUrl"`
	SkipTLSVerify bool       `json:"skipTLSVerify"`
	Status        string     `json:"status"`
	Message       string     `json:"message"`
	LastCheckAt   *time.Time `json:"lastCheckAt"`
	Description   string     `json:"description"`
	CreatedAt     time.Time  `json:"createdAt"`
	UpdatedAt     time.Time  `json:"updatedAt"`
}

type OpenNodeOption struct {
	ID      uint   `json:"id"`
	Name    string `json:"name"`
	Addr    string `json:"addr"`
	Value   string `json:"value"`
	Status  string `json:"status"`
	Version string `json:"version"`
	IsXpack bool   `json:"isXpack"`
	IsBound bool   `json:"isBound"`
	Message string `json:"message"`
}
