# frozen_string_literal: true

# A passkey's public key as text: where a String is varchar(255)
# (MySQL), an RSA key, 363 characters at 2048 bits, would not fit. Its
# NOT NULL kept. SQLite keeps any length in any column, so its table
# is left as it is rather than copied anew to say so.
Sequel.migration do
    up do
        next if database_type == :sqlite
        alter_table(:passkeys) do
            set_column_type :public_key, String, text: true
        end
    end

    down do
        next if database_type == :sqlite
        alter_table(:passkeys) { set_column_type :public_key, String }
    end
end
