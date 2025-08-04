package router

import "github.com/gin-gonic/gin"

func SetupRoutes() *gin.Engine {
	// Define your routes here
	// Example:
	// http.HandleFunc("/api/v1/resource", resourceHandler)
	router := gin.Default()
	return router
}
