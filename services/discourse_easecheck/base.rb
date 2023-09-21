# frozen_string_literal: true

# name: discourse-easecheck
# about: check texts and iamges using cloud service
# version: 0.2
# authors: WANG WEI FENG
# url: https://gitee.com/opensourceway/discourse-easecheck.git

require 'faraday/logging/formatter'
require 'json'

module DiscourseEaseCheck
  class Base
    def self.debug_log(info)
        Rails.logger.warn("EaseCheck Debugging: #{info}") if SiteSetting.easecheck_debug_info
    end

    def self.block_log(info)
        Rails.logger.warn("EaseCheck Block: #{info}")
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

    def self.json_walk(result, user_json, prop, custom_path)
        path = custom_path
        if path.present?
          #this.[].that is the same as this.that, allows for both this[0].that and this.[0].that path styles
          path = path.gsub(".[].", ".").gsub(".[", "[")
          segments = parse_segments(path)
          val = walk_path(user_json, segments)
          result[prop] = val if val.present?
        end
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
  end
end
