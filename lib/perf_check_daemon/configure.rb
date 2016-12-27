
require 'httparty'
require 'resque'

require 'sqlite3'
require 'active_record'

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
  root = File.expand_path("#{File.dirname(__FILE__)}/../..")
  if ENV['RACK_ENV'] == 'test'
    YAML.load_file("#{root}/config/daemon.yml.example").to_ostruct
  else
    YAML.load_file("#{root}/config/daemon.yml").to_ostruct
  end
end

def github
  config.github
end

def gist_template
  root = File.expand_path("#{File.dirname(__FILE__)}/../..")
  "#{root}/config/gist.erb"
end

def api(path, data={}, put: false, post: false)
  page_info = api_page(path, data, put: put, post: post)

  data = page_info.data
  while page_info.next
    page_info = api_page(page_info.next, data)
    data.concat(page_info.data)
  end

  data
end

def api_page(path, data, put: false, post: false)
  path.sub!(/^\//, '')
  url = path.match(/^https?:/) ? path : "https://api.github.com/#{path}"

  options = {
    query: { access_token: github.token },
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
    link = api_parse_next_link(resp)
    OpenStruct.new(data: JSON.parse(resp.body), next: link)
  elsif resp.success?
    OpenStruct.new(data: true, next: nil)
  end
end

def api_parse_next_link(resp)
  if header = resp.headers['link']
    header.split(',').each do |link|
      if link =~ /<(.+)>;\s*rel="(.+)"/ && $2 == 'next'
        return $1
      end
    end
  end

  nil
end

def api_log(path, resp)
  limit = resp.headers['x-ratelimit-limit']
  remaining = resp.headers['x-ratelimit-remaining']
  used = limit.to_i - remaining.to_i

  severity = resp.success? ? Logger::DEBUG : Logger::WARN

  tail = "(#{used}/#{limit}): /#{path}"
  app_logger.log(severity, "GITHUB #{resp.code} #{tail}")
  app_logger.warn(resp.body) unless resp.success?
end

def app_logger
  @app_logger ||= Logger.new(STDERR)
end

config.redis = {
  host: config.host || 'localhost',
  port: 6379
}.merge((config.redis || {}).to_h).to_ostruct

# Resque.inline = true
Resque.redis = Redis.new(config.redis.to_h)

root = File.expand_path("#{File.dirname(__FILE__)}/../..")
if ENV['RACK_ENV'] == 'test'
  dbfile = "#{root}/db/daemon-test.sqlite3"
else
  dbfile = "#{root}/db/daemon.sqlite3"
end

ActiveRecord::Base.establish_connection(
  adapter: "sqlite3",
  database: dbfile
)
