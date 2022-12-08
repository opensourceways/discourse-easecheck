# frozen_string_literal: true

=begin
Achieve interface for moderation by Validator
This is called in plugins/chat/app/model/chat_message.rb
=end
class ChatModeratorValidator < ActiveModel::EachValidator
    def validate_each(record, attribute, value)
        
        suggestion, matches = Moderator.should_block_txt? value, 'article'
        if suggestion.nil?
            key = "sensitive_check_failed"
            record.errors.add(attribute, I18n.t(key))
            return
        end
        if suggestion == "block"
            if matches.size == 0    
                key = "contains_sensitive_exp"
                record.errors.add(attribute, I18n.t(key))
            elsif matches.size == 1
                key = 'contains_sensitive_word'
                translation_args = { word: CGI.escapeHTML(matches[0]) }
                record.errors.add(attribute, I18n.t(key, translation_args))
            else
                key = 'contains_sensitive_words'
                translation_args = { words: CGI.escapeHTML(matches.join(', ')) }
                record.errors.add(attribute, I18n.t(key, translation_args))
            end
       
        end
    end

end
