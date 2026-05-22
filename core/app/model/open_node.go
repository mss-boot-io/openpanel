package model

import "time"

type OpenNode struct {
	BaseModel
	Name          string     `json:"name" gorm:"not null;unique"`
	BaseURL       string     `json:"baseUrl" gorm:"not null"`
	APIKey        string     `json:"apiKey" gorm:"not null"`
	SkipTLSVerify bool       `json:"skipTLSVerify"`
	Status        string     `json:"status"`
	Message       string     `json:"message"`
	LastCheckAt   *time.Time `json:"lastCheckAt"`
	Description   string     `json:"description"`
}

func (o OpenNode) TableName() string {
	return "open_nodes"
}
