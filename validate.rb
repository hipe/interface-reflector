require File.dirname(__FILE__)+'/templite'

module Hipe; end
module Hipe::InterfaceReflector

  # straightforward validation and normalization library

  # Totally standalone from the rest of this thing (except for templite), can
  # optionally integrate with a controller / app that is CLI or otherwise.

  # The object that has this as an ancestor must respond to 'request' and
  # 'response'.  The request must respond to [].  (No attempt at making
  # indifferent access with symbol vs. string-keys happens here.)

  # Validation methods may perform normalization that will change elements of
  # the request object, and if so the request must respond to []=

  # The response object must respond to
  #   add_error_message(msg [,prop_name [,label]])

  # The most common validations of the author are provided here.  To extend
  # with your own validations, override build_validator() in your host class
  # / module and subclass Validator or otherwise provide your own
  # implementation for custom validation methods.  (A convention is for
  # validation methods to contain 'must' in them, but some do not for the sake
  # of brevity, like "string_range")

  # A validation method call must return true on success, false on failure.
  # On failure, the validation method will typically call
  # add_error_message(..) on the response object.

  module Validate
    def build_validator
      Validator.new self
    end
    def validate
      @validator ||= build_validator
    end
  end
  class Validator
    def initialize host
      @host = host
      @queue = nil
    end
    def request;  @host.request end
    def response; @host.response end
    # common validations
    def file_must_exist *a
      true == x = preamble(:file_must_exist, a) or return x
      unless File.exist?(request[a.first])
        return invalid("File not found: #{request[a.first].inspect}", a)
      end
      true
    end
    def must_be_number *a
      true == x = preamble(:must_be_number, a) or return x
      case val = request[a.first]
      when Fixnum, Float;
        true
      when String
        if md = %r{\A-?\d+(\.\d+)?\Z}.match(val)
          request[a.first] = md[1] ? val.to_f : val.to_i
          true
        else
          invalid "Needed number, had {value} for {label}.", a
        end
      else
        invalid "Needed number, had {value} for {label}.", a
      end
    end
    alias_method :must_be_float, :must_be_number
    def must_be_integer *a
      true == x = preamble(:must_be_integer, a) or return x
      must_be_number(*a) or return false
      val = request[a.first]
      case val
      when Fixnum
        true
      when Float
        (val % 1.0 == 0.0) ? true :
          invalid("Needed integer, had {value} for {label}.", a)
      else
        invalid "Needed integer, had {value} for {label}.", a
      end
    end
    def must_be_positive *a
      true == x = preamble(:must_be_positive, a) or return x
      must_be_number(*a) or return false
      if request[a.first] <= 0
        return invalid("{label} must be positive, had {value}.", a)
      end
      true
    end
    def string_length min, max, *a
      val = request[a.first]
      unless String === val
        return invalid("Needed string, had {value} for {label}.", a)
      end
      bad = false
      min and val.length < min and bad = true and invalid(
        "{label} must be at least #{min} characters.", a)
      max and val.length > max and bad = true and invalid(
        "{label} cannot be longer than #{max} characters.", a)
      not bad
    end
    # common validations end
    def invalid msg, a
      if msg.index('{')
        msg = Templite.new(msg).render(template_datasource(a))
      end
      response.add_error_message msg, *a
      false
    end
    def template_datasource a
      @tds ||= Class.new.class_eval do
        def initialize v; @validator = v                                   end
        def _set(a); @prop_name, @label, @msg = *a; self                   end
        def value; @validator.request[@prop_name].inspect                  end
        def label; @label || @prop_name.to_s                               end
        self
      end.new(self)
      @tds._set a
    end
    def preamble name, a
      a.empty? and return aggregate(name)
      @queue.nil? || flush(a)
    end
    def aggregate name
      (@queue ||= []).push name
      self
    end
    def flush a
      while name = @queue.shift
        send(name, *a) or return false
      end
      true
    end
  end
end
