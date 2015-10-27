
require 'httparty'
require 'resque'

require 'ostruct'
require 'yaml'
require 'json'

require 'logger'

class Hash
  def to_ostruct
    o = OpenStruct.new(self)
    each.with_object(o) do |(k, v), o|
      o.send(:"#{k}=", v.to_ostruct) if v.respond_to? :to_ostruct
    end
    o
  end
end

def config
  root = File.expand_path("#{File.dirname(__FILE__)}/..")
  YAML.load_file("#{root}/config/daemon.yml").to_ostruct
end

def gist_template
  root = File.expand_path("#{File.dirname(__FILE__)}/..")
  "#{root}/config/gist.erb"
end

def comment_template
  root = File.expand_path("#{File.dirname(__FILE__)}/..")
  "#{root}/config/comment.erb"
end

def api(path, data={}, put: false, post: false)
  path.sub!(/^\//, '')
  url = path.match(/^https?:/) ? path : "https://api.github.com/#{path}"

  options = {
    query: { access_token: config.github.token },
    body: data.to_json
  }

  if put
    resp = HTTParty.put(url, options)
  elsif post
    resp = HTTParty.post(url, options)
  else
    resp = HTTParty.get(url, options)
  end

  api_log(path, resp)

  if resp.success? && resp.body
    JSON.parse(resp.body)
  elsif resp.success?
    true
  end
end

def api_log(path, resp)
  json = JSON.parse(resp.body) if resp.body

  limit = resp.headers['x-ratelimit-limit']
  remaining = resp.headers['x-ratelimit-remaining']
  used = limit.to_i - remaining.to_i

  severity = resp.success? ? Logger::INFO : Logger::WARN

  tail = "(#{used}/#{limit}): /#{path}"
  if json.is_a?(Hash) && json['message']
    logger.log(severity, "GITHUB #{resp.code} \"#{json['message']}'\" #{tail}")
  else
    logger.log(severity, "GITHUB #{resp.code} #{tail}")
  end
end

def logger
  @logger ||= Logger.new(STDERR)
end

config.redis = {
  host: 'localhost',
  port: 6379
}.merge((config.redis || {}).to_h).to_ostruct


Resque.redis = Redis.new(config.redis.to_h)
