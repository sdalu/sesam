# frozen_string_literal: true

require "json"

require "sesam/store"

module Sesam
    class JsonStore
        # The document on disk: read and checked, written whole.
        module Disk
            # The document format this sesam reads and writes.
            FORMAT = 1

            # The document at `path`, empty tables for an absent file;
            # TooNew past this sesam's format, Error for what is not a
            # document of this shape.
            def self.read(path)
                return empty unless File.exist?(path)
                doc = JSON.parse(File.read(path), symbolize_names: true)
                check(path, doc)
                doc
            rescue JSON::ParserError
                raise Error, "#{path} is not a JSON document"
            end

            def self.empty
                { sesam: FORMAT, ids: JsonStore::IDS.to_h { [it, 0] },
                  **JsonStore::TABLES.to_h { [it, []] } }
            end

            def self.check(path, doc)
                unless doc.is_a?(Hash) && doc[:sesam].is_a?(Integer)
                    raise Error, "#{path} is not a sesam document"
                end
                if doc[:sesam] > FORMAT
                    raise Schema::TooNew, "#{path} is at format " \
                                          "#{doc[:sesam]}, this sesam knows " \
                                          "up to #{FORMAT}: update it"
                end
                return if shaped?(doc)
                raise Error, "#{path} is not a sesam document"
            end

            def self.shaped?(doc)
                doc[:sesam] == FORMAT && doc[:ids].is_a?(Hash) &&
                    JsonStore::IDS.all? { doc[:ids][it].is_a?(Integer) } &&
                    JsonStore::TABLES.all? { table?(doc[it]) }
            end

            def self.table?(rows) = rows.is_a?(Array) && rows.all?(Hash)

            # A temp file beside the document, fsynced and renamed over
            # it, then the directory fsynced: an interrupted write leaves
            # the old document whole. A rewrite keeps the file's mode, a
            # new one is 0600.
            def self.write(path, doc)
                text = generated(path, doc)
                tmp = "#{path}.#{Process.pid}.#{rand(1 << 32)}.tmp"
                save(tmp, text, File.exist?(path) ? File.stat(path) : nil)
                File.rename(tmp, path)
                File.open(File.dirname(path), &:fsync)
            ensure
                File.unlink(tmp) if tmp && File.exist?(tmp)
            end

            # The document as text; Error for what JSON cannot hold (text
            # not UTF-8), before anything is written.
            def self.generated(path, doc)
                "#{JSON.pretty_generate(doc)}\n"
            rescue JSON::GeneratorError => e
                raise Error, "#{path}: not written, #{e.message}"
            end

            # The old file's mode, and its owner where the writer may
            # give it (root running a tool on the application's file,
            # which would otherwise be left to root alone).
            def self.save(tmp, text, old)
                mode = old ? old.mode & 0o7777 : 0o600
                flags = File::WRONLY | File::CREAT | File::EXCL
                File.open(tmp, flags, mode) do |file|
                    file.chmod(mode)
                    file.chown(old.uid, old.gid) if old && Process.euid.zero?
                    file.write(text)
                    file.fsync
                end
            end
        end
    end
end
