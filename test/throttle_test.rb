# frozen_string_literal: true

require "test_helper"

# Failures counted per key over a window; the count keeps only what
# still counts.
class ThrottleTest < Minitest::Test
    Throttle = Sesam::Throttle
    NOW = Time.utc(2026, 11, 15, 12)

    def test_failures_counted_in_the_window
        throttle = Throttle.new(window: 900)
        5.times { throttle.failed!("k", now: NOW) }
        assert throttle.blocked?("k", 5, now: NOW + 899)
        refute throttle.blocked?("k", 5, now: NOW + 901)
    end

    def test_a_key_cleared_starts_again
        throttle = Throttle.new(window: 900)
        5.times { throttle.failed!("k", now: NOW) }
        throttle.clear!("k")
        refute throttle.blocked?("k", 5, now: NOW)
    end

    def test_keys_are_counted_apart
        throttle = Throttle.new(window: 900)
        5.times { throttle.failed!("a", now: NOW) }
        refute throttle.blocked?("b", 5, now: NOW)
    end

    def test_unknown_keys_are_not_kept
        throttle = Throttle.new(window: 900)
        1000.times { throttle.blocked?("try:#{it}", 5, now: NOW) }
        throttle.failed!("try:x", now: NOW)
        throttle.blocked?("try:x", 5, now: NOW + 901)
        assert_equal 0, throttle.size
    end

    # Past SWEEP keys, a failure drops every key whose failures lapsed.
    def test_many_keys_are_swept
        throttle = Throttle.new(window: 900)
        Throttle::SWEEP.times { throttle.failed!("old:#{it}", now: NOW) }
        throttle.failed!("new", now: NOW + 901)
        assert_equal 1, throttle.size
    end
end
