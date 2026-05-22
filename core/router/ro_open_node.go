package router

import (
	v2 "github.com/1Panel-dev/1Panel/core/app/api/v2"
	"github.com/1Panel-dev/1Panel/core/middleware"
	"github.com/gin-gonic/gin"
)

type OpenNodeRouter struct{}

func (s *OpenNodeRouter) InitRouter(Router *gin.RouterGroup) {
	openNodeRouter := Router.Group("open-nodes").
		Use(middleware.SessionAuth()).
		Use(middleware.PasswordExpired())
	baseApi := v2.ApiGroupApp.BaseApi
	{
		openNodeRouter.POST("/search", baseApi.SearchOpenNode)
		openNodeRouter.GET("/options", baseApi.ListOpenNodeOptions)
		openNodeRouter.POST("", baseApi.CreateOpenNode)
		openNodeRouter.POST("/update", baseApi.UpdateOpenNode)
		openNodeRouter.POST("/del", baseApi.DeleteOpenNode)
		openNodeRouter.POST("/test", baseApi.TestOpenNode)
	}
}
