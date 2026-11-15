# frozen_string_literal: true

require "test_helper"

# A challenge spends once; what lapsed is forgotten.
class SpentTest < Minitest::Test
    NOW = Time.utc(2026, 11, 15, 12)

    def test_a_value_spends_once
        spent = Sesam::Spent.new(window: 300)
        assert spent.spend!("abc", now: NOW)
        refute spent.spend!("abc", now: NOW + 299)
        assert spent.spend!("def", now: NOW)
    end

    def test_what_lapsed_is_forgotten
        spent = Sesam::Spent.new(window: 300)
        spent.spend!("abc", now: NOW)
        assert spent.spend!("abc", now: NOW + 301)
    end
end
