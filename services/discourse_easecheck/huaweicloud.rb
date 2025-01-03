# frozen_string_literal: true

# name: discourse-easecheck
# about: check texts and iamges using cloud service
# version: 0.2
# authors: WANG WEI FENG
# url: https://gitee.com/opensourceway/discourse-easecheck.git

require 'faraday/logging/formatter'
require 'json'
require_relative 'base'

module DiscourseEaseCheck
  class HuaweiCloud < Base
    def self.cache_key
        "easecheck_huaweicloud"
    end

    def self.is_token_expired?
        existing_token = Discourse.redis.get(cache_key)
        if existing_token
            false
        else
            true
        end
    end

    def self.refresh_token?
        count = 0
        while !get_token?
            count += 1
            if count >= 10
                return false
            end
            sleep 1
        end
        true
    end

    def self.get_token?
        debug_log("get token start...")
        connection = Faraday.new do |f|
            f.adapter Faraday.default_adapter
        end
        auth_url = SiteSetting.easecheck_huaweicloud_auth_token_endpoint
                   .sub(':project_name', SiteSetting.easecheck_huaweicloud_project_name)    
        auth_method = "POST".downcase.to_sym
        auth_body = {
            auth: {
                identity: {
                    methods: ["password"],
                    password: {
                        user: {
                            domain: {
                                name: ENV["SENSITIVE_DOMAIN_NAME"]
                            },
                            name: ENV["SENSITIVE_NAME"],
                            password: ENV["SENSITIVE_PASSWORD"]
                        }
                    }
                },
                scope: {
                    project: {
                        id: SiteSetting.easecheck_huaweicloud_project_id,
                        name: SiteSetting.easecheck_huaweicloud_project_name
                    }
                }
            }
        }.to_json
        auth_body = JSON.parse(auth_body).to_s.gsub('=>', ':')
        auth_headers = { 'Content-Type' => 'application/json;charset=utf8' }
        
        begin
            response = connection.run_request(auth_method, auth_url, auth_body, auth_headers)
     
            if response.status == 200 || response.status == 201
                result = response.headers
                Discourse.redis.setex(cache_key,
                                      SiteSetting.easecheck_huaweicloud_token_validity_period.hours.to_i,
                                      result['x-subject-token'])
                true
            else
                debug_log("token response: #{response.inspect}")
                debug_log("token status: #{response.status}")
                false
            end
        rescue => e         
            debug_log("auth_url: #{auth_url}")
            debug_log("auth_body: #{auth_body}")
            debug_log("request faild: #{e.message}")
            debug_log("Backtrace: #{e.backtrace.join("\n")}") # 输出栈跟踪信息
            raise RuntimeError.new("get token failed: #{e.message}\n#{e.backtrace.join("\n")}")
        end        
        
    end

    def self.text_request_body(text)
        body = {}
        body[:items] = [{text: text}.stringify_keys]
        body[:categories] = SiteSetting.easecheck_huaweicloud_text_check_categories.split(',')
        json_body = JSON.parse body.to_json
        json_body.to_s.gsub('=>', ':')
    end

    def self.image_request_body(image)
        body = {}
        body[:categories] = SiteSetting.easecheck_huaweicloud_image_check_categories.split(',')
        body[:image] = image
        json_body = JSON.parse body.to_json
        json_body.to_s.gsub('=>', ':')
    end

    def self.request_for_text_check(text)
        debug_log("text check start...")
        if is_token_expired?
            if !refresh_token?
                return nil
            end
        end

        connection = Faraday.new do |f|
            f.adapter Faraday.default_adapter
        end
        text_check_method = "POST".downcase.to_sym
        text_check_url = SiteSetting.easecheck_huaweicloud_text_check_endpoint
                              .sub(':project_id', SiteSetting.easecheck_huaweicloud_project_id)
                              .sub(':project_name', SiteSetting.easecheck_huaweicloud_project_name)
        body = text_request_body(text)
        bearer_token = "#{Discourse.redis.get(cache_key)}"
        headers = { 'X-Auth-Token' => bearer_token, 'Content-Type' => 'application/json;charset=utf8' }
        
        begin
            response = connection.run_request(text_check_method, text_check_url, body, headers)

            if response.status == 200
                text_check_json = JSON.parse(response.body)
    
                debug_log("text check response: #{text_check_json}")
    
                result = {}
                if text_check_json.present?
                    json_walk(result, text_check_json, :suggestion, "result.suggestion")
                    json_walk(result, text_check_json, :detail, "result.detail")
                end
                result
            else
                debug_log("text check body: #{body}")
                debug_log("text_check_url: #{text_check_url}")
                debug_log("headers: #{headers}")
                refresh_token?
                nil
            end
        rescue => e      
            debug_log("request faild: #{e.message}")
            debug_log("Backtrace: #{e.backtrace.join("\n")}") # 输出栈跟踪信息
            raise RuntimeError.new("text check failed: #{e.message}\n#{e.backtrace.join("\n")}")
        end
        
    end

    def self.request_for_image_check(img)
        debug_log("image check start...")
        if is_token_expired?
            if !refresh_token?
                return nil
            end
        end

        connection = Faraday.new do |f|
            f.adapter Faraday.default_adapter
        end
        image_check_method = "POST".downcase.to_sym
        image_check_url = SiteSetting.easecheck_huaweicloud_image_check_endpoint
                               .sub(':project_id', SiteSetting.easecheck_huaweicloud_project_id)
                               .sub(':project_name', SiteSetting.easecheck_huaweicloud_project_name)
        body = image_request_body(img)
        bearer_token = "#{Discourse.redis.get(cache_key)}"
        headers = { 'X-Auth-Token' => bearer_token, 'Content-Type' => 'application/json' }
        
        begin
            response = connection.run_request(image_check_method, image_check_url, body, headers)
            if response.status == 200
                image_check_json = JSON.parse(response.body)
    
                debug_log("image check response: #{image_check_json}")
    
                result = {}
                if image_check_json.present?
                    json_walk(result, image_check_json, :suggestion, "result.suggestion")
                    json_walk(result, image_check_json, :category_suggestions, "result.category_suggestions")
                end
                result
            else
                debug_log("image_body: #{body}")
                debug_log("image_check_url: #{image_check_url}")
                debug_log("headers: #{headers}")
                refresh_token?
                nil
            end
        rescue => e
            debug_log("request faild: #{e.message}")
            debug_log("Backtrace: #{e.backtrace.join("\n")}") # 输出栈跟踪信息
            raise RuntimeError.new("image check failed: #{e.message}\n#{e.backtrace.join("\n")}")
        end
        
    end

    def self.process_text_response(result)
        # check fail
        if result.nil?
            return [nil, ""]
        end

        if result[:suggestion] == "pass" || result[:detail].empty?
            [result[:suggestion], ""]
        else
            detail = ""
            result[:detail].each do |key, value|
                detail = detail + key.to_s + "=>" + value.to_s + ", "
            end
            block_log("block text detail: #{detail}")
            [result[:suggestion], detail.slice(0, detail.length - 2)]
        end
    end

    def self.process_image_response(result)
        # check fail
        if result.nil?
            return [nil, ""]
        end

        if result[:suggestion] == "pass"
            ["pass", ""]
        else
            detail = ""
            result[:category_suggestions].each do |key, value|
              detail = detail + key.to_s + "=>" + value.to_s + ", "
            end
            block_log("block image detail: #{detail}")
            [result[:suggestion], detail.slice(0, detail.length - 2)]
        end
    end

    def self.run_text_check(text)
        unless SiteSetting.easecheck_enabled
            return ["pass", ""]
        end
        begin
            Timeout.timeout(55) do
                (0..text.size).step(5000) do |start_index|
                    subText = text[start_index, 5000]
                    suggestion, detail = process_text_response(request_for_text_check(subText))
                    if suggestion.nil? || suggestion == "block" || suggestion == "review"
                        return suggestion, detail
                    end
                end
            end
        rescue Timeout::Error
            return ["fail", ""]
        end
        ["pass", ""]
    end

    def self.run_image_check(img)
        process_image_response request_for_image_check(img)
    end
  end
end
