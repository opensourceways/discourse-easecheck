# frozen_string_literal: true

=begin
Achieve interface for moderation by Validator
=end
class ImageModeratorValidator < ActiveModel::EachValidator
    def validate_each(record, attribute, value)
        suggestion = ::Moderator.should_block_image? value, 'article', SiteSetting.sensitive_image_check_categories

        if suggestion.nil?
            key = "sensitive_check_failed"
            record.errors.add(attribute, I18n.t(key))
            return
        end

        if suggestion == "block"
            key = "contains_sensitive_image"
            record.errors.add(attribute, I18n.t(key)) 
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