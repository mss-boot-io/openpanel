package repo

import (
	"github.com/1Panel-dev/1Panel/core/app/model"
	"github.com/1Panel-dev/1Panel/core/global"
	"gorm.io/gorm"
)

type OpenNodeRepo struct{}

type IOpenNodeRepo interface {
	Page(page, size int, opts ...global.DBOption) (int64, []model.OpenNode, error)
	List(opts ...global.DBOption) ([]model.OpenNode, error)
	Get(opts ...global.DBOption) (model.OpenNode, error)
	Create(node *model.OpenNode) error
	Update(id uint, vars map[string]interface{}) error
	Delete(opts ...global.DBOption) error

	WithByInfo(info string) global.DBOption
}

func NewIOpenNodeRepo() IOpenNodeRepo {
	return &OpenNodeRepo{}
}

func (u *OpenNodeRepo) Page(page, size int, opts ...global.DBOption) (int64, []model.OpenNode, error) {
	var nodes []model.OpenNode
	db := global.DB.Model(&model.OpenNode{})
	for _, opt := range opts {
		db = opt(db)
	}
	count := int64(0)
	db = db.Count(&count)
	err := db.Limit(size).Offset(size * (page - 1)).Find(&nodes).Error
	return count, nodes, err
}

func (u *OpenNodeRepo) List(opts ...global.DBOption) ([]model.OpenNode, error) {
	var nodes []model.OpenNode
	db := global.DB.Model(&model.OpenNode{})
	for _, opt := range opts {
		db = opt(db)
	}
	err := db.Find(&nodes).Error
	return nodes, err
}

func (u *OpenNodeRepo) Get(opts ...global.DBOption) (model.OpenNode, error) {
	var node model.OpenNode
	db := global.DB
	for _, opt := range opts {
		db = opt(db)
	}
	err := db.First(&node).Error
	return node, err
}

func (u *OpenNodeRepo) Create(node *model.OpenNode) error {
	return global.DB.Create(node).Error
}

func (u *OpenNodeRepo) Update(id uint, vars map[string]interface{}) error {
	return global.DB.Model(&model.OpenNode{}).Where("id = ?", id).Updates(vars).Error
}

func (u *OpenNodeRepo) Delete(opts ...global.DBOption) error {
	db := global.DB
	for _, opt := range opts {
		db = opt(db)
	}
	return db.Delete(&model.OpenNode{}).Error
}

func (u *OpenNodeRepo) WithByInfo(info string) global.DBOption {
	return func(g *gorm.DB) *gorm.DB {
		if info == "" {
			return g
		}
		return g.Where("name LIKE ? OR base_url LIKE ?", "%"+info+"%", "%"+info+"%")
	}
}
