# frozen_string_literal: true

# name: EaseCheck
# about: check sensitive texts and iamges
# version: 0.1
# authors: WANG WEI FENG
# url: https://gitee.com/opensourceway/EaseCheck.git


enabled_site_setting :sensitive_enabled

require 'faraday/logging/formatter'
require 'json'

load File.expand_path("../../../lib/new_post_manager.rb", __FILE__)
load File.expand_path("../../../app/services/word_watcher.rb", __FILE__)
load File.expand_path("../lib/validators/post_moderator_validator.rb", __FILE__)
load File.expand_path("../lib/validators/title_moderator_validator.rb", __FILE__)
load File.expand_path("../lib/validators/image_moderator_validator.rb", __FILE__)
load File.expand_path("../lib/validators/chat_moderator_validator.rb", __FILE__)

=begin
This class is designed for Huawei Cloud Moderation service.
The purpose is to perform texts or images sensitive check
request and return processed response.
For texts, it returns process suggestion and hits words.
For images, it only returns process suggestion.
=end
class ::Moderator
    def self.cache_key
        "easecheck_moderator"
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
        connection = Faraday.new do |f| 
            f.adapter FinalDestination::FaradayAdapter
        end
        auth_url = SiteSetting.sensitive_auth_url.sub(':project_name', SiteSetting.sensitive_project_name)
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
                        id: SiteSetting.sensitive_project_id,
                        name: SiteSetting.sensitive_project_name
                    }
                }
            }
        }.to_json
        auth_body = JSON.parse(auth_body).to_s.gsub('=>', ':')
        auth_headers = { 'Content-Type' => 'application/json;charset=utf8' }
        response = connection.run_request(auth_method, auth_url, auth_body, auth_headers)
        log("sensitive token response: #{response.inspect}")

        if response.status == 201 or response.status == 200
            if SiteSetting.sensitive_auth_token_loc == "headers"
                result = response.headers
                Discourse.redis.setex(cache_key, 24.hours.to_i, result['x-subject-token'])            
                true
            elsif SiteSetting.sensitive_auth_token_loc == "body"
                auth_json = JSON.parse(response.body)
                log("sensitive_token_json: #{auth_json}")
                result = {}
                if auth_json.present?
                    json_walk(result, auth_json, :token)
                end
                Discourse.redis.setex(cache_key, 24.hours.to_i, result[:token]) 
                true
            end
        else
            false
        end
    end

    def self.log(info)
        Rails.logger.warn("Sensitive Check Debugging: #{info}") if SiteSetting.sensitive_debug_info
    end

    def self.text_request_body(text, event_type)
        body = {}
        body[:items] = [{text: text}.stringify_keys]
        body[:categories] = ["porn", "abuse", "contraband", "flood", "politics"]
        json_body = JSON.parse body.to_json
        json_body.to_s.gsub('=>', ':')
    end

    def self.image_request_body(image, event_type, categories)
        body = {}
        body[:categories] = categories if categories
        body[:image] = image
        json_body = JSON.parse body.to_json
        json_body.to_s.gsub('=>', ':')
    end

    def self.json_walk(result, user_json, prop, custom_path: nil)
        path = custom_path || SiteSetting.public_send("sensitive_json_#{prop}_path")
        if path.present?
          #this.[].that is the same as this.that, allows for both this[0].that and this.[0].that path styles
          path = path.gsub(".[].", ".").gsub(".[", "[")
          segments = parse_segments(path)
          val = walk_path(user_json, segments)
          result[prop] = val if val.present?
        end
    end

    def self.parse_segments(path)
        segments = [+""]
        quoted = false
        escaped = false
    
        path.split("").each do |char|
            next_char_escaped = false
            if !escaped && (char == '"')
                quoted = !quoted
            elsif !escaped && !quoted && (char == '.')
                segments.append +""
            elsif !escaped && (char == '\\')
                next_char_escaped = true
            else
                segments.last << char
            end
            escaped = next_char_escaped
        end
    
        segments
    end

    def self.walk_path(fragment, segments, seg_index = 0)
        first_seg = segments[seg_index]
        return if first_seg.blank? || fragment.blank?
        return nil unless fragment.is_a?(Hash) || fragment.is_a?(Array)
        first_seg = segments[seg_index].scan(/([\d+])/).length > 0 ? first_seg.split("[")[0] : first_seg
        if fragment.is_a?(Hash)
            deref = fragment[first_seg] || fragment[first_seg.to_sym]
        else
            array_index = 0
            if (seg_index > 0)
                last_index = segments[seg_index - 1].scan(/([\d+])/).flatten() || [0]
                array_index = last_index.length > 0 ? last_index[0].to_i : 0
            end
            if fragment.any? && fragment.length >= array_index - 1
                deref = fragment[array_index][first_seg]
            else
                deref = nil
            end
        end
    
        if (deref.blank? || seg_index == segments.size - 1)
            deref
        else
            seg_index += 1
            walk_path(deref, segments, seg_index)
        end
    end

    def self.process_txt_response(result)
        if result.nil?
            return nil, []
        end

        suggestion = result[:suggestion]
        if suggestion == SiteSetting.sensitive_block_exp and result[:hits].empty?
            return "block", []
        elsif suggestion == SiteSetting.sensitive_review_exp
            return "review", []
        elsif suggestion == SiteSetting.sensitive_pass_exp
            return "pass", []
        end

        hits = result[:hits].to_s.gsub('=>', ':')
        return "block", hits
    end

    def self.process_img_response(result)
        if result.nil?
            return nil
        end

        suggestion = result[:suggestion]
        if suggestion == SiteSetting.sensitive_block_exp
            return "block"
        elsif suggestion == SiteSetting.sensitive_review_exp
            return "review"
        elsif suggestion == SiteSetting.sensitive_pass_exp
            return "pass"
        end
    end

=begin
Function: Request for texts sensitive check
Input: 
    Texts to check -- string
    Event type -- string
Output:
    Suggestion -- pass/review/block, string
    Hits -- hits words, list
=end
    def self.request_for_text_moderation(text, event)
        if is_token_expired?
            if !refresh_token?
                return nil
            end
        end

        connection = Faraday.new do |f| 
            f.adapter FinalDestination::FaradayAdapter
        end
        text_moderation_method = SiteSetting.sensitive_text_check_method.downcase.to_sym
        text_moderation_url = SiteSetting.sensitive_text_check_url.sub(':project_id', SiteSetting.sensitive_project_id).sub(':project_name', SiteSetting.sensitive_project_name)
        body = text_request_body(text, event)
        bearer_token = "#{Discourse.redis.get(cache_key)}"
        headers = { 'X-Auth-Token' => bearer_token, 'Content-Type' => 'application/json;charset=utf8' }
        log("request body: #{body}")

        response = connection.run_request(text_moderation_method, text_moderation_url, body, headers)
        log("text_check_response: #{response.inspect}")

        if response.status == 200
            text_check_json = JSON.parse(response.body)

            log("text_check_json: #{text_check_json}")

            result = {}
            if text_check_json.present?
                json_walk(result, text_check_json, :suggestion)
                json_walk(result, text_check_json, :hits)
            end
            result
        else
            refresh_token?
            nil
        end
    end

=begin
Function: Request for images sensitive check
Input: 
    Images to check -- string
    Event type -- string
    Categories -- terrorism/porn/ad/all, string
Output:
    Suggestion -- pass/review/block, string
=end 
    def self.request_for_image_moderation(img, event, categories)
        if is_token_expired?
            if !refresh_token?
                return nil
            end
        end

        connection = Faraday.new do |f| 
            f.adapter FinalDestination::FaradayAdapter
        end
        image_moderation_method = SiteSetting.sensitive_image_check_method.downcase.to_sym
        image_moderation_url = SiteSetting.sensitive_image_check_url.sub(':project_id', SiteSetting.sensitive_project_id).sub(':project_name', SiteSetting.sensitive_project_name)
        body = image_request_body(img, event, categories)
        bearer_token = "#{Discourse.redis.get(cache_key)}"
        headers = { 'X-Auth-Token' => bearer_token, 'Content-Type' => 'application/json' }
        log("request body: #{body}")

        response = connection.run_request(image_moderation_method, image_moderation_url, body, headers)
        log("image_check_response: #{response.inspect}")

        if response.status == 200
            image_check_json = JSON.parse(response.body)

            log("image_check_json: #{image_check_json}")

            result = {}
            if image_check_json.present?
                json_walk(result, image_check_json, :suggestion)
            end
            result
        else
            refresh_token?
            nil
        end
    end

    def self.should_block_txt?(text, event)
        response = request_for_text_moderation(text, event)
        process_txt_response(response)
    end

    def self.should_block_image?(img, event, categories)
        response = request_for_image_moderation(img, event, categories)
        process_img_response(response)
    end
end


=begin
Achieve interface for moderation by inheritance.
This is temporarily deprecated.
=end
class WordModerator < WordWatcher
=begin
Doubt: use a modeler to check each action, which is equivalent to adding the same vocabulary to each action
Function: Inherit the focus word matching function, and add the modeler check result to the original result list
Input: action, whether to match all concerned words
Output: hit word list
TIPS: The function is only used to find the hit word of the corresponding action, and no subsequent action is performed
=end
    def word_matches_for_action?(action, event_type, all_matches: false)
        matched_words = []
        res = Moderator.new.request_for_text_moderation @raw, event_type
        
        matched_words.concat res, super(action, all_matches)
        return if matched_words.blank?

        matched_words.compact!
        matched_words.uniq!
        matched_words.sort!
        matched_words
    end

=begin
Function: shield the concerned words and the hit words of Moderator
Input: html format
Output: nil
TIPS: shielding after hit
=end
    def self.censor(html)
        doc = Nokogiri::HTML5::fragment(html)
        doc.traverse do |node|
            log("before censor: #{node.content}")
            segments = Moderator.new.request_for_text_moderation(node.content) if node.text?
            log("text_moderator_segments: #{segments}")
            segments.each do |segment|
                node.content = censor_text_with_regexp(node.content, segment) if node.text?
            end
            log("after censor: #{node.content}")
        end
        
        html = doc.to_html
        super(html)
    end

=begin
Function: shield the concerned words and the hit words of Moderator
Input: text to be checked
Output: nil
TIPS: shielding after hit
=end
    def self.censor_text(text)
        return text if text.blank?
        log("before censor: #{text}")
        segments = Moderator.new.request_for_text_moderation(text)
        log("text_moderator_segments: #{segments}")
        segments.inject(text) do |txt, segment| 
            censor_text_with_regexp(txt, segment)
        end
        log("after censor: #{text}")
        super
    end
end


=begin
Achieve interface for moderation by NewPostManager
handler.
This achieves manual review.
=end
class ModeratorValidator < ActiveModel::EachValidator
    def validate_each(record, attribute, value)
        # presence(record)

        return if record.acting_user.try(:staged?)
        return if record.acting_user.try(:admin?) && Discourse.static_doc_topic_ids.include?(record.topic_id)

        suggestion, matches = Moderator.should_block_txt? value, 'article'
        if suggestion.nil?
            key = "sensitive_check_failed"
            record.errors.add(attribute, I18n.t(key))
            return
        end
        if suggestion == "block" or suggestion == "review"
            key = "sensitive_check_review"
            record.errors.add(attribute, key)
        end
    end

    def presence(post)
        unless options[:skip_topic]
            post.errors.add(:topic_id, :blank, **options) if post.topic_id.blank?
        end
    
        if post.new_record? && post.user_id.nil?
            post.errors.add(:user_id, :blank, **options)
        end
    end
end


NewPostManager.add_handler priority=9 do |manager|
    if manager.user.staff?
        nil
        next
    end
    validator = ModeratorValidator.new(attributes: [:raw])
    post = Post.new(raw: "#{manager.args[:title]} #{manager.args[:raw]}")
    post.user = manager.user
    validator.validate(post) if !post.acting_user&.staged
    

    if post.errors[:raw].present?
        if post.errors[:raw].include? "sensitive_check_review"
            result = manager.enqueue(:sensitive_check_review)
            result
        else
            result = NewPostResult.new(:created_post, false)
            result.errors.add(:base, post.errors[:raw])
            result
        end
    else
        nil
    end
end
