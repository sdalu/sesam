# frozen_string_literal: true

# Every moment sesam keeps, as milliseconds since the epoch in an
# integer (Sesam::Stamp): a time column reads through the Sequel
# timezone of whichever process reads it. Each row's moment is read
# here as this process reads it, so the conversion is right only when
# it runs with the Sequel timezone the rows were written with, as an
# application migrating its own database does; run otherwise, every
# moment shifts by the offset between the two, and nothing here can
# tell. Each column replaced in place: added, filled, the old dropped
# (SQLite 3.35 or later), the new renamed, NOT NULL set back.
Sequel.migration do
    up do
        # Each table's key, its moments, and those that may be missing.
        tables = {
            users: [:name, %i[sessions_since created_at], [:sessions_since]],
            user_keys: [:id, %i[created_at], []],
            user_addresses: [:address, %i[created_at], []],
            invites: [:id, %i[created_at expires_at used_at], [:used_at]],
            passkeys: [:id, %i[created_at], []]
        }
        tables.each do |table, (key, columns, optional)|
            fresh = columns.to_h { [it, :"#{it}_ms"] }
            alter_table(table) do
                fresh.each_value { add_column it, :Bignum }
            end
            self[table].select(key, *columns).each do |row|
                self[table].where(key => row[key]).update(
                    fresh.to_h { |old, new| [new, row[old] && Sesam::Stamp.ms(row[old])] }
                )
            end
            alter_table(table) do
                fresh.each_key { drop_column it }
                fresh.each { |old, new| rename_column new, old }
                (columns - optional).each { set_column_not_null it }
            end
        end
    end

    down do
        raise Sequel::Error, "sesam's times are not migrated back"
    end
end
