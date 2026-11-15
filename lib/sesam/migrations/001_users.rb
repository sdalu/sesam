# frozen_string_literal: true

# Users by name (their login), a password's scrypt hash when one is
# set, the moment before which their sessions no longer count, and
# when they were added; their API keys and invitations as SHA-256
# digests; the LAN addresses they are known at; their passkeys, the
# public half of each device's key pair. A user's keys, invitations,
# addresses and passkeys go with them. Each table made only where
# missing: a database that already holds them (ClimatControl's, made
# before sesam) keeps them as they are.
Sequel.migration do
    up do
        create_table?(:users) do
            String :name, primary_key: true
            String :password
            Time :sessions_since
            Time :created_at, null: false
        end
        create_table?(:user_keys) do
            primary_key :id
            foreign_key :user, :users, type: String, null: false,
                                       on_delete: :cascade
            String :digest, null: false, unique: true
            String :label
            Time :created_at, null: false
        end
        create_table?(:user_addresses) do
            String :address, primary_key: true
            foreign_key :user, :users, type: String, null: false,
                                       on_delete: :cascade
            Time :created_at, null: false
        end
        create_table?(:invites) do
            primary_key :id
            foreign_key :user, :users, type: String, null: false,
                                       on_delete: :cascade
            String :digest, null: false, unique: true
            Time :created_at, null: false
            Time :expires_at, null: false
            Time :used_at
        end
        create_table?(:passkeys) do
            String :id, primary_key: true
            foreign_key :user, :users, type: String, null: false,
                                       on_delete: :cascade
            String :public_key, null: false
            Integer :sign_count, null: false, default: 0
            String :label, null: false
            Time :created_at, null: false
        end
    end

    down do
        drop_table(:passkeys, :invites, :user_addresses, :user_keys, :users)
    end
end
