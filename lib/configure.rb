
require 'httparty'

require 'ostruct'
require 'yaml'
require 'json'

class Hash
  def to_ostruct
    o = OpenStruct.new(self)
    each.with_object(o) do |(k, v), o|
      o.send(:"#{k}=", v.to_ostruct) if v.respond_to? :to_ostruct
    end
    o
  end
end

def secrets
  root = File.expand_path("#{File.dirname(__FILE__)}/..")
  YAML.load_file("#{root}/config/secrets.yml").to_ostruct
end

def github
  root = File.expand_path("#{File.dirname(__FILE__)}/..")
  YAML.load_file("#{root}/config/github.yml").to_ostruct
end

def app
  root = File.expand_path("#{File.dirname(__FILE__)}/..")
  YAML.load_file("#{root}/config/app.yml").to_ostruct
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
    query: { access_token: secrets.github.token },
    body: data.to_json
  }

  if put
    resp = HTTParty.put(url, options)
  elsif post
    resp = HTTParty.post(url, options)
  else
    resp = HTTParty.get(url, options)
  end

  JSON.parse(resp.body) if resp.body
end
