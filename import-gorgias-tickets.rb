require 'yaml'
require 'rest-client'
require 'json'
require 'mongo'

config = YAML.load_file('config.yml')

required_config_paths = [
  ['database', 'host'],
  ['database', 'port'],
  ['database', 'name'],
  ['gorgias_api', 'url'],
  ['gorgias_api', 'username'],
  ['gorgias_api', 'api_key'],
  ['rate_limit', 'requests'],
  ['rate_limit', 'interval'],
]

def fetch_value(hash, keys)
  key = keys.shift
  return hash[key] if keys.empty?
  return nil unless hash[key].is_a?(Hash)
  fetch_value(hash[key], keys)
end

# Check each required configuration path
required_config_paths.each do |path|
  value = fetch_value(config.dup, path.dup) # Dup to avoid modifying the original arrays
  if value.nil? || value.to_s.strip.empty?
    puts "Missing or empty configuration for: #{path.join(' > ')}"
    exit(1)
  end
end

API_URL = config['gorgias_api']['url']
API_KEY = config['gorgias_api']['api_key']
GORGIAS_USER = config['gorgias_api']['username']
RATE_LIMIT = config['rate_limit']['requests']
RATE_LIMIT_SECONDS = config['rate_limit']['interval']

valid_users = config['gorgias_api']['valid_users'].split(',')
default_user = config['gorgias_api']['default_user']

Mongo::Logger.logger.level = Logger::WARN
client = Mongo::Client.new([config['database']['host'] + ':' + config['database']['port'].to_s], :database => config['database']['name'])
conversations_collection = client[:conversations]

def base_header(hdrs={})
  {
    'content-type' => 'text/json; charset=UTF-8'
  }.merge(hdrs)
end

def gorgias_request(path, method: :get, payload: nil)
  check_rate_limit

  full_url = "#{API_URL}/#{path}"

  # Prepare headers
  headers = { accept: :json }

  # Prepare the request options
  options = {
    method: method,
    url: full_url,
    user: GORGIAS_USER,
    password: API_KEY,
    headers: headers
  }

  # Add payload if method is :post and payload is provided
  if method == :post && payload
    options[:payload] = payload.is_a?(Hash) ? payload.to_json : payload
    options[:headers].merge!(content_type: :json)
  end

  # Execute the request
  response = RestClient::Request.execute(options)

  # Return the response body
  response.body
rescue RestClient::ExceptionWithResponse => e
  # Handle HTTP errors
  e.response
end

def check_rate_limit
  return if RATE_LIMIT.zero?
  now = Time.now
  @requests ||= []
  # ignore requests more than RATE_LIMIT_SECONDS ago
  since = now - RATE_LIMIT_SECONDS
  @requests.each_with_index do |t, i|
    if t > since
      if i > 0
        @requests = @requests[i..-1]
      end
      break
    end
  end
  if @requests.size >= RATE_LIMIT
    since_secs = (now - @requests[0]).to_i
    sleep (RATE_LIMIT_SECONDS-since_secs)+1
  end
  @requests ||= []
  @requests << now
end

# Start the script

# test a gorgias API call
ticket = {
  :channel => 'api',
  :created_datetime => '2024-02-05T14:42:00.384938',
  :customer => { :email => 'bryce@rubus.ltd' },
  :external_id => '12347',
  :status => "open",
  :subject => "Agent Message Test 2",
  :updated_datetime => '2024-02-05T15:42:00.384938',
  :from_agent => true,
  :messages => [
      {
        :body_html => "Hello,<br><br>        This is a new message<br><br>        Megan",
        :body_text => "Hello,\n\n        This is a new message\n\n        Megan",
        :subject => "Agent Message Test 2",
        :channel => "api",
        :created_datetime => '2024-02-05T14:42:00.384938',
        :sent_datetime => '2024-02-05T14:42:00.384938',
        :from_agent => true,
        :message_id => "<1210577922@web>",
        :via => 'api',
        :sender => { :email => 'megan@drbrighten.com' },
        :receiver => { :email => 'bryce@rubus.ltd' },
      },
      {
        :body_html => "Hola,<br><br>This is my response.<br><br> Bryce ",
        :body_text => "Hola,\n\nThis is my response.\n\n Bryce ",
        :subject => "Re: Agent Message Test 2",
        :channel => "api",
        :created_datetime => '2024-02-05T15:42:00.384938',
        :sent_datetime => '2024-02-05T15:42:00.384938',
        :from_agent => false,
        :message_id => "<1210577955@web>",
        :via => 'api',
        :sender => { :email => 'bryce@rubus.ltd' },
      }
    ],
  :tags => [
      {
        :name => "helpscout"
      }
    ],
}
# tickets = gorgias_request('tickets', method: :post, payload: ticket.to_json)
# puts tickets
# exit

query = {
  '$and' => [
    {
      '$or' => [
        { 'gorgias_id' => { '$exists' => false } },
        { 'gorgias_id' => { '$lte' => 0, '$type' => 'int' } }
      ]
    },
    { 'source.type' => 'email' }
  ]
}
conversations_cursor = conversations_collection.find(query)
conversations_cursor.each do |conv|

  puts "Starting " + conv['number'].to_s
  customer_email = conv.dig('primaryCustomer', 'email')
  ticket = {
    :channel => 'api',
    :created_datetime => conv['createdAt'],
    :customer => { :email => customer_email },
    :external_id => conv['number'].to_s,
    :status => "closed",
    :subject => conv["subject"],
    :updated_datetime => conv["userUpdatedAt"],
    :tags => [
      {
        :name => "helpscout"
      }
    ],
  }

  created_by_type = conv.dig('createdBy', 'type')
  if (created_by_type == 'customer')
    ticket[:from_agent] = false
  else
    ticket[:from_agent] = true
  end

  messages = []
  conv["threads"].each do |thread|
    if thread['body']
      message = {
        :body_html => thread['body'],
        :body_text => thread['body'].gsub(/<\/?[^>]*>/, ""),
        :subject => conv["subject"],
        :channel => "api",
        :created_datetime => thread['createdAt'],
        :sent_datetime => thread['createdAt'],
        :message_id => "<" + thread["id"].to_s + "@web>",
        :via => 'api',
      }
      t_created_by_email = thread.dig("createdBy", "email")
      if thread["createdBy"]["type"] == "customer"
        message["sender"] = { :email => t_created_by_email }
        message["from_agent"] = false
      else
        sender = valid_users.include?(t_created_by_email) ? t_created_by_email : default_user
        customer_email = thread.dig("customer", "email")
        message["sender"] = { :email => sender }
        message["receiver"] = { :email => customer_email }
        message["from_agent"] = true
      end
      messages << message
    end
  end

  ticket[:messages] = messages
  
  g_req = gorgias_request('tickets', method: :post, payload: ticket.to_json)
  g_ticket = JSON.parse(g_req)
  if g_ticket["id"]
    conversations_collection.update_one({ _id: conv['_id'] }, { '$set' => { gorgias_id: g_ticket["id"] } })
    puts conv["number"].to_s + " = " + g_ticket["id"].to_s
  end
end
