# frozen_string_literal: true

require "open3"

require "web_support"

# What the application defines is its own: sesam's defaults fill only
# what is missing, before or after it registers sesam. Helpers come as
# modules (a method defined on the class itself wins anyway).
class ExtensionTest < Minitest::Test
    include WebSupport

    def build
        Class.new(Sinatra::Base) do
            helpers(Module.new { def answer(data) = "mine:#{data.to_json}" })
            register Sesam::Sinatra
        end
    end

    def test_an_application_s_own_answer_is_kept
        app = build
        assert_equal "mine:1", app.new!.answer(1)
        assert_equal({}, app.new!.sesam_profile("alice"))
    end

    # Neither /secret nor its gate defines its own answer or refuse, so
    # both must carry sesam's own Content-Type, not Sinatra's text/html
    # default for an untyped body.
    def test_default_replies_are_json
        assert_equal 200, call(:get, "/secret", peer: LAN)
        assert_match(%r{\Aapplication/json}, last_response.content_type)

        assert_equal 401, call(:get, "/secret")
        assert_match(%r{\Aapplication/json}, last_response.content_type)
    end

    def test_one_defined_after_registering_wins
        later = Class.new(Sinatra::Base) do
            register Sesam::Sinatra
            helpers(Module.new { def sesam_profile(_name) = { mine: true } })
        end
        assert_equal({ mine: true }, later.new!.sesam_profile("x"))
    end

    def test_without_sinatra_the_require_says_so
        hide = <<~RUBY
            module Kernel
                alias_method :was, :require
                def require(n) = n == "sinatra/base" ? raise(LoadError, n) : was(n)
            end
            require "sesam/sinatra"
        RUBY
        _, err, = Open3.capture3(RbConfig.ruby, "-Ilib", "-e", hide)
        assert_match(/needs the sinatra gem/, err)
    end
end
