require "bundler/inline"

gemfile(true) do
  source "https://rubygems.org"

  git_source(:github) { |repo| "https://github.com/#{repo}.git" }

  gem "rails", github: "rails/rails"
  gem "sqlite3"
  gem "byebug"
  gem 'pry-rails'
end

require "active_record"
require "minitest/autorun"
require "logger"
require '/Users/siddhantbajaj/Desktop/scripts/softer_delete.rb'

# This connection will do for database-independent bug reports.
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
#ActiveRecord::Base.logger = Logger.new(STDOUT)

ActiveRecord::Schema.define do
  create_table :products, force: true do |t|
    t.string :title
    t.datetime :updated_at
    t.datetime :deleted_at
    t.boolean :is_not_deleted, index: true, default: true
  end

  create_table :comments, force: true do |t|
    t.integer :product_id
  end
end

class Product < ActiveRecord::Base
  include SofterDelete::UsingIsNotDeleted
  has_many :comments, dependent: :destroy
  after_commit :fire_destroy_webhook, on: :destroy
  after_save :saved
  after_update :in_update

  def fire_destroy_webhook
    puts "In destroy"
  end

  def saved
    puts "In save"
  end

  def in_update
    puts "In update"
  end  
end

class Comment < ActiveRecord::Base
  belongs_to :product, touch: true
  after_commit :fire_create_webhook, on: :destroy

  def fire_create_webhook
    puts "In comment"
  end
end

class Testing
  def self.blah
    product = Product.create!
    comment = Comment.create!
    product.comments << comment
    Product.transaction do
      comment.destroy! if comment
      product = Product.find(comment.product_id)
      product.destroy!
    end
  end
end

Testing.blah



# OUTPUT
#   =>In save
#   =>In Comment
