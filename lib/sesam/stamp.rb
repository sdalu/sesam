# frozen_string_literal: true

module Sesam
    # A moment as sesam keeps it: whole milliseconds since the epoch, an
    # integer. A time column is read through the Sequel timezone of the
    # process reading it, and one reading without the writer's setting
    # shifts every moment by its offset (an ended session counting for
    # an hour more); an integer reads the same everywhere. Milliseconds,
    # as sessions are stamped: in seconds, a session given in the same
    # second before its user's sessions were ended would still count.
    module Stamp
        def self.ms(time) = (time.to_r * 1000).floor

        # The Time `ms` is, local; nil for nil (a moment not yet come).
        def self.time(ms) = ms && Time.at(Rational(ms, 1000))

        # `row` with each of `columns` as a Time.
        def self.times(row, *columns)
            row.merge(columns.to_h { [it, time(row[it])] })
        end
    end
end
