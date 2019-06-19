# Copyright 2015 FUJITSU LIMITED
# Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except
# in compliance with the License. You may obtain a copy of the License at
# http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software distributed under the License
# is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express
# or implied. See the License for the specific language governing permissions and limitations under
# the License.

# encoding: utf-8

require 'json'
require 'rest-client'

# relative requirements
require_relative '../helper/url_helper'

module Monasca

  # Base class for Monasca log API clients. Subclasses should implement a
  # request method.
  class BaseLogAPIClient

    def initialize(host, version, log)
      @rest_client_url = Helper::UrlHelper.generate_url(host, '/' + version).to_s
      @rest_client = RestClient::Resource.new(@rest_client_url)
      @log = log
    end

    # Return whether the client supports bulk log message transmission.
    # If true, the client should implement a send_logs_bulk method.
    def supports_bulk?
      false
    end

    # Send logs to monasca-log-api, requires token
    def send_log(message, token, dimensions, application_type = nil)
      request(message, token, dimensions, application_type)
      @log.debug("Successfully sent log=#{message}, with token=#{token} and dimensions=#{dimensions} to monasca-log-api")
    rescue => e
      @log.warn('Sending message to monasca-log-api threw exception', exceptionew: e)
      raise
    end
  end

  # Monasca log API V2.0 client.
  class LogAPIV2Client < BaseLogAPIClient

    private

    def request(message, token, dimensions, application_type)
      post_headers = {
        x_auth_token: token,
        content_type: 'text/plain'
      }

      # Dimensions should be a comma-separated list of comma-separated
      # key-value pairs.
      if dimensions
        joined = dimensions.map do |k, v|
          [k, v].join(':')
        end
        post_headers[:x_dimensions] = joined.join(',')
      end

      post_headers[:x_application_type] = application_type if application_type

      @rest_client['log']['single'].post(message, post_headers)
    end
  end

  # Monasca log API V3.0 client.
  class LogAPIV3Client < BaseLogAPIClient

    # Return whether the client supports bulk log message transmission.
    # If true, the client should implement a send_logs_bulk method.
    def supports_bulk?
      true
    end

    # Send multiple logs to monasca-log-api, requires token
    # logs should be an Array of Arrays: [[message, dimensions], ...]
    def send_logs_bulk(logs, token, dimensions, application_type = nil)
      request_bulk(logs, token, dimensions, application_type)
      @log.debug("Successfully sent bulk logs, with token=#{token} and dimensions=#{dimensions} to monasca-log-api")
    rescue => e
      @log.warn('Bulk sending messages to monasca-log-api threw exception', exceptionew: e)
      raise
    end

    private

    def request(message, token, dimensions, application_type)
      # NOTE: X-ApplicationType is not supported for V3 API.
      post_headers = {
        x_auth_token: token,
        content_type: 'application/json'
      }

      data = {
        "dimensions" => dimensions,
        "logs" => [{
          "message" => message,
          # Currently monasca errors if per-message dimensions are omitted.
          "dimensions" => {}
        }]
      }.to_json

      @rest_client['logs'].post(data, post_headers)
    end

    # logs should be an Array of Arrays: [[message, dimensions], ...]
    def request_bulk(logs, token, dimensions, application_type)
      # NOTE: X-ApplicationType is not supported for V3 API.
      post_headers = {
        x_auth_token: token,
        content_type: 'application/json'
      }

      data = {
        "dimensions" => dimensions,
        "logs" => logs.map {|message, log_dimensions|
          {
            "message" => message,
            # Currently monasca errors if per-message dimensions are omitted.
            "dimensions" => log_dimensions,
          }
        }
      }.to_json

      @rest_client['logs'].post(data, post_headers)
    end
  end

  # Create and return a monasca log API client suitable for the requested API
  # version.
  def self.get_log_api_client(host, version, log)
    tmp_version = version.sub('v', '')
    if tmp_version == '2.0'
      LogAPIV2Client.new(host, version, log)
    elsif tmp_version == '3.0'
      LogAPIV3Client.new(host, version, log)
    else
      raise "#{tmp_version} is not supported, supported versions are 2.0, 3.0"
    end
  end
end
