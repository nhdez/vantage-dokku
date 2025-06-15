# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_06_15_155004) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "activity_logs", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "action", null: false
    t.text "details"
    t.string "ip_address"
    t.text "user_agent"
    t.datetime "occurred_at", null: false
    t.string "controller_name"
    t.string "action_name"
    t.text "params_data"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["action"], name: "index_activity_logs_on_action"
    t.index ["occurred_at"], name: "index_activity_logs_on_occurred_at"
    t.index ["user_id", "occurred_at"], name: "index_activity_logs_on_user_id_and_occurred_at"
    t.index ["user_id"], name: "index_activity_logs_on_user_id"
  end

  create_table "app_settings", force: :cascade do |t|
    t.string "key", null: false
    t.text "value"
    t.string "description"
    t.string "setting_type", default: "string"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_app_settings_on_key", unique: true
  end

  create_table "database_configurations", force: :cascade do |t|
    t.bigint "deployment_id", null: false
    t.string "database_type", null: false
    t.string "database_name", null: false
    t.string "username"
    t.string "password"
    t.boolean "redis_enabled", default: false, null: false
    t.string "redis_name"
    t.boolean "configured", default: false, null: false
    t.text "configuration_output"
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["database_name"], name: "index_database_configurations_on_database_name", unique: true
    t.index ["deployment_id"], name: "index_database_configurations_on_deployment_id", unique: true
  end

  create_table "deployment_ssh_keys", force: :cascade do |t|
    t.bigint "deployment_id", null: false
    t.bigint "ssh_key_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["deployment_id", "ssh_key_id"], name: "index_deployment_ssh_keys_on_deployment_id_and_ssh_key_id", unique: true
    t.index ["deployment_id"], name: "index_deployment_ssh_keys_on_deployment_id"
    t.index ["ssh_key_id"], name: "index_deployment_ssh_keys_on_ssh_key_id"
  end

  create_table "deployments", force: :cascade do |t|
    t.string "name", null: false
    t.string "dokku_app_name", null: false
    t.text "description"
    t.bigint "server_id", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "uuid", null: false
    t.index ["dokku_app_name"], name: "index_deployments_on_dokku_app_name", unique: true
    t.index ["server_id", "dokku_app_name"], name: "index_deployments_on_server_id_and_dokku_app_name", unique: true
    t.index ["server_id"], name: "index_deployments_on_server_id"
    t.index ["user_id", "name"], name: "index_deployments_on_user_id_and_name", unique: true
    t.index ["user_id"], name: "index_deployments_on_user_id"
    t.index ["uuid"], name: "index_deployments_on_uuid", unique: true
  end

  create_table "domains", force: :cascade do |t|
    t.bigint "deployment_id", null: false
    t.string "name", null: false
    t.boolean "ssl_enabled", default: false, null: false
    t.boolean "default_domain", default: false, null: false
    t.text "ssl_error_message"
    t.datetime "ssl_configured_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["deployment_id", "default_domain"], name: "index_domains_on_deployment_id_and_default_domain"
    t.index ["deployment_id", "name"], name: "index_domains_on_deployment_id_and_name", unique: true
    t.index ["deployment_id"], name: "index_domains_on_deployment_id"
  end

  create_table "environment_variables", force: :cascade do |t|
    t.bigint "deployment_id", null: false
    t.string "key", null: false
    t.text "value"
    t.string "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["deployment_id", "key"], name: "index_environment_variables_on_deployment_id_and_key", unique: true
    t.index ["deployment_id"], name: "index_environment_variables_on_deployment_id"
  end

  create_table "oauth_settings", force: :cascade do |t|
    t.string "key", null: false
    t.text "value"
    t.text "description"
    t.boolean "enabled", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_oauth_settings_on_key", unique: true
  end

  create_table "roles", force: :cascade do |t|
    t.string "name"
    t.string "resource_type"
    t.bigint "resource_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name", "resource_type", "resource_id"], name: "index_roles_on_name_and_resource_type_and_resource_id"
    t.index ["resource_type", "resource_id"], name: "index_roles_on_resource"
  end

  create_table "servers", force: :cascade do |t|
    t.string "name", null: false
    t.string "ip", null: false
    t.string "username", default: "root"
    t.string "internal_ip"
    t.integer "port", default: 22
    t.string "service_provider"
    t.string "uuid", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "password"
    t.string "os_version"
    t.string "ram_total"
    t.string "cpu_model"
    t.integer "cpu_cores"
    t.string "disk_total"
    t.datetime "last_connected_at"
    t.string "connection_status", default: "unknown"
    t.string "dokku_version"
    t.index ["connection_status"], name: "index_servers_on_connection_status"
    t.index ["last_connected_at"], name: "index_servers_on_last_connected_at"
    t.index ["user_id", "name"], name: "index_servers_on_user_id_and_name"
    t.index ["user_id"], name: "index_servers_on_user_id"
    t.index ["uuid"], name: "index_servers_on_uuid", unique: true
  end

  create_table "ssh_keys", force: :cascade do |t|
    t.string "name", null: false
    t.text "public_key", null: false
    t.datetime "expires_at"
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "name"], name: "index_ssh_keys_on_user_id_and_name", unique: true
    t.index ["user_id"], name: "index_ssh_keys_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "first_name"
    t.string "last_name"
    t.date "date_of_birth"
    t.string "theme", default: "auto"
    t.string "provider"
    t.string "uid"
    t.string "google_avatar_url"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["theme"], name: "index_users_on_theme"
  end

  create_table "users_roles", id: false, force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "role_id"
    t.index ["role_id"], name: "index_users_roles_on_role_id"
    t.index ["user_id", "role_id"], name: "index_users_roles_on_user_id_and_role_id"
    t.index ["user_id"], name: "index_users_roles_on_user_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "activity_logs", "users"
  add_foreign_key "database_configurations", "deployments"
  add_foreign_key "deployment_ssh_keys", "deployments"
  add_foreign_key "deployment_ssh_keys", "ssh_keys"
  add_foreign_key "deployments", "servers"
  add_foreign_key "deployments", "users"
  add_foreign_key "domains", "deployments"
  add_foreign_key "environment_variables", "deployments"
  add_foreign_key "servers", "users"
  add_foreign_key "ssh_keys", "users"
end
