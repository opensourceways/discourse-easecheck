# frozen_string_literal: true

=begin
Achieve interface for moderation by Validator
This is called in model/post.rb
=end
class PostModeratorValidator < ActiveModel::EachValidator
    def validate_each(record, attribute, value)
        return if record.acting_user.try(:staged?)
        return if record.acting_user.try(:admin?) && Discourse.static_doc_topic_ids.include?(record.topic_id)

        suggestion, matches = ::Moderator.should_block_txt? value, 'article'
        
        if suggestion.nil?
            key = "sensitive_check_failed"
            record.errors.add(attribute, I18n.t(key))
            return
        end

        if suggestion == "block"
            if matches.size == 0    
                key = "contains_sensitive_exp"
                record.errors.add(attribute, I18n.t(key))
            else
                key = 'contains_sensitive_words'
                translation_args = { words: matches }
                record.errors.add(attribute, I18n.t(key, translation_args))
            end
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