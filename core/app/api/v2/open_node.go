package v2

import (
	"github.com/1Panel-dev/1Panel/core/app/api/v2/helper"
	"github.com/1Panel-dev/1Panel/core/app/dto"
	"github.com/gin-gonic/gin"
)

// @Tags Open Node
// @Summary Search open nodes
// @Accept json
// @Param request body dto.OpenNodeSearch true "request"
// @Success 200 {object} dto.PageResult
// @Security ApiKeyAuth
// @Security Timestamp
// @Router /core/open-nodes/search [post]
func (b *BaseApi) SearchOpenNode(c *gin.Context) {
	var req dto.OpenNodeSearch
	if err := helper.CheckBindAndValidate(&req, c); err != nil {
		return
	}
	total, items, err := openNodeService.Search(req)
	if err != nil {
		helper.InternalServer(c, err)
		return
	}
	helper.SuccessWithData(c, dto.PageResult{Total: total, Items: items})
}

// @Tags Open Node
// @Summary List open node options
// @Success 200 {array} dto.OpenNodeOption
// @Security ApiKeyAuth
// @Security Timestamp
// @Router /core/open-nodes/options [get]
func (b *BaseApi) ListOpenNodeOptions(c *gin.Context) {
	options, err := openNodeService.ListOptions()
	if err != nil {
		helper.InternalServer(c, err)
		return
	}
	helper.SuccessWithData(c, options)
}

// @Tags Open Node
// @Summary Create open node
// @Accept json
// @Param request body dto.OpenNodeCreate true "request"
// @Success 200
// @Security ApiKeyAuth
// @Security Timestamp
// @Router /core/open-nodes [post]
func (b *BaseApi) CreateOpenNode(c *gin.Context) {
	var req dto.OpenNodeCreate
	if err := helper.CheckBindAndValidate(&req, c); err != nil {
		return
	}
	if err := openNodeService.Create(req); err != nil {
		helper.InternalServer(c, err)
		return
	}
	helper.Success(c)
}

// @Tags Open Node
// @Summary Update open node
// @Accept json
// @Param request body dto.OpenNodeUpdate true "request"
// @Success 200
// @Security ApiKeyAuth
// @Security Timestamp
// @Router /core/open-nodes/update [post]
func (b *BaseApi) UpdateOpenNode(c *gin.Context) {
	var req dto.OpenNodeUpdate
	if err := helper.CheckBindAndValidate(&req, c); err != nil {
		return
	}
	if err := openNodeService.Update(req); err != nil {
		helper.InternalServer(c, err)
		return
	}
	helper.Success(c)
}

// @Tags Open Node
// @Summary Delete open node
// @Accept json
// @Param request body dto.OperateByID true "request"
// @Success 200
// @Security ApiKeyAuth
// @Security Timestamp
// @Router /core/open-nodes/del [post]
func (b *BaseApi) DeleteOpenNode(c *gin.Context) {
	var req dto.OperateByID
	if err := helper.CheckBindAndValidate(&req, c); err != nil {
		return
	}
	if err := openNodeService.Delete(req.ID); err != nil {
		helper.InternalServer(c, err)
		return
	}
	helper.Success(c)
}

// @Tags Open Node
// @Summary Test open node
// @Accept json
// @Param request body dto.OpenNodeTest true "request"
// @Success 200 {object} dto.OpenNodeInfo
// @Security ApiKeyAuth
// @Security Timestamp
// @Router /core/open-nodes/test [post]
func (b *BaseApi) TestOpenNode(c *gin.Context) {
	var req dto.OpenNodeTest
	if err := helper.CheckBindAndValidate(&req, c); err != nil {
		return
	}
	info, err := openNodeService.Test(req)
	if err != nil {
		helper.InternalServer(c, err)
		return
	}
	helper.SuccessWithData(c, info)
}
