#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'

require 'excon'

PUMA_STATEFILE = '/tmp/puma_2655.yaml'

DEFAULT_EXCON_PARAMS = {
  connect_timeout: 0.5,
  read_timeout: 0.5,
  write_timeout: 0.5,
}.freeze

$read_timeout = 0.5

def puma_stats
  begin
    state = YAML.load_file(PUMA_STATEFILE)
    uri = URI.parse(state.fetch('control_url'))

    excon_params = DEFAULT_EXCON_PARAMS.dup
    excon_params[:socket] = uri.path
    excon_params[:read_timeout] = $read_timeout

    connection = Excon.new('unix://', excon_params)

    query = {}
    if state.key?('control_auth_token')
      query[:token] = state.fetch('control_auth_token')
    end

    response = connection.request(
      method: :get,
      path: '/stats',
      query: query,
      expects: [200],
    )
    
    # If the request is successful, reduce read_timeout by 10%
    $read_timeout *= 0.9

    response.body

  rescue Excon::Error::Timeout => e
    # If the request timed out, increase read_timeout by 5%
    $read_timeout *= 1.05
    "Error: #{e.class} (#{e.message})"

  rescue => e
    "Error: #{e.class} (#{e.message})"
  end
end

def main(_args)
  # Start a thread to send requests to the main server, in order to trigger
  # object allocation and GC.
  t = Thread.new do
    while true
      Excon.get('http://localhost:9292/')
      sleep 0.1
    end
  end

  # Hammer the control server with /stats requests
  while true
    puts puma_stats
    sleep 0.1
  end
end

if $PROGRAM_NAME == __FILE__
  main(ARGV)
end
