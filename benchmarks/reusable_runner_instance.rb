require 'bundler'
Bundler.setup
require 'middleware'
require 'benchmark/ips'


class FrontParamsValidator
  def initialize(app)
    @app = app
  end

  def call(env)
    if errors = validate_params(env[:front_params])
      env[:response][:errors] = errors
    else
      @app.call(env)
    end
  end

  def validate_params(params)
    if false
      return [{msg: 'Bad format for param xyz!'}]
    end
  end
end

class ApiParamsGenerator
  def initialize(app)
    @app = app
  end

  def call(env)
    (env[:api_params]||={})[:modified] = true
    res = @app.call(env)
    env[:api_params][:after] = true
    env
  end
end


class ResponseModifier
  def initialize(app)
    @app = app
  end

  def call(env)
    @app.call(env)
    env[:response][:works] = true
    env
  end
end

class ResponseMultiModifier
  def initialize(app, value)
    @app = app
    @value = value
  end

  def call(env)
    @app.call(env)
    (env[:response][:multi_modifier]||=[]) << 'called with ' + @value
    env
  end
end

class ExceptionHandling
  def initialize(app)
    @app = app
  end

  def call(env)
    begin
      @app.call env
    rescue => ex
      puts ex
      puts ex.backtrace
      hash = { :message => ex.to_s }
      hash[:backtrace] = ex.backtrace
      env['api.errors'] = MultiJson.dump(hash)
      env
    end
  end
end


class PrepareEnvironment
  def initialize(app)
    @app = app
  end

  def call(env)
    env[:response]||= {}
    env[:api_params]||= {}
    @app.call(env)
  end
end

class ApiDirect
  def self.call(env)
    begin
      env[:response]||= {}
      env[:api_params]||= {}
      if errors = validate_params(env[:front_params])
        env[:response][:errors] = errors
      else
        (env[:api_params]||={})[:modified] = true
        env[:response][:works] = true

        (env[:response][:multi_modifier]||=[]) << 'called with ' + 'first'
        (env[:response][:multi_modifier]||=[]) << 'called with ' + 'second'
        env[:api_params][:after] = true
      end

    rescue => ex
      puts ex
      puts ex.backtrace
      hash = { :message => ex.to_s }
      hash[:backtrace] = ex.backtrace
      env['api.errors'] = MultiJson.dump(hash)
      env
    end
  end

  def self.validate_params(params)
    if false
      return [{msg: 'Bad format for param xyz!'}]
    end
  end
end


ApiStack = Middleware::Builder.new do
  use ExceptionHandling
  use PrepareEnvironment
  use FrontParamsValidator
  use ApiParamsGenerator
  use ResponseModifier
  use ResponseMultiModifier, 'first'
  use ResponseMultiModifier, 'second'
end


ApiStackReuse = Middleware::Builder.new(reuse_instance: true) do
  use ExceptionHandling
  use PrepareEnvironment
  use FrontParamsValidator
  use ApiParamsGenerator
  use ResponseModifier
  use ResponseMultiModifier, 'first'
  use ResponseMultiModifier, 'second'
end

Benchmark.ips do |x|
  x.time   = 2
  x.warmup = 1

  x.report("normal stack") {
    env = {}
    ApiStack.call(env)
  }

  x.report("reuse stack") {
    env = {}
    ApiStackReuse.call(env)
  }

  x.report("direct implementation") {
    env = {}
    ApiDirect.call(env)
  }

  x.compare!
end
