# frozen_string_literal: true

# name: discourse-easecheck
# about: check texts and iamges using cloud service
# version: 0.2
# authors: WANG WEI FENG
# url: https://gitee.com/opensourceway/discourse-easecheck.git

enabled_site_setting :easecheck_enabled

require 'faraday/logging/formatter'
require 'json'

after_initialize do
  module ::DiscourseEaseCheck
    class EaseCheckError < ::StandardError; end

    PLUGIN_NAME = "discourse_easecheck".freeze

    autoload :HuaweiCloud,
              "#{Rails.root}/plugins/discourse-easecheck/services/discourse_easecheck/huaweicloud"

    class Engine < ::Rails::Engine
      engine_name PLUGIN_NAME
      isolate_namespace DiscourseEaseCheck
    end
  end

  class ::EaseCheckTextValidator < ActiveModel::EachValidator
    def validate_each(record, attribute, value)
      return if record.acting_user.try(:admin?)

      return if value.blank?

      suggestion, detail = "DiscourseEaseCheck::#{SiteSetting.easecheck_provider}".constantize.run_text_check(value)

      if suggestion.nil?
        err = I18n.t("easecheck_failed")
        record.errors.add(:base, err)
      elsif suggestion == "block" || suggestion == "review"
        translation_args = { detail: detail }
        err = I18n.t("easecheck_contains_unallowed_text", translation_args)
        record.errors.add(:base, err)
      end
    end
  end

  NewPostManager.add_handler priority=9 do |manager|
    if manager.user.staff?
      nil
      next
    end

    validator = EaseCheckTextValidator.new(attributes: [:raw])
    post = Post.new(raw: "#{manager.args[:title]} #{manager.args[:raw]}")
    post.user = manager.user
    validator.validate(post)

    if post.errors[:base].present?
      result = manager.enqueue(:easecheck_need_review)
      result
    else
      nil
    end
  end

  class ::Post < ActiveRecord::Base
    validates :raw, ease_check_text: true, unless: Proc.new { |v| v.new_record? }
  end

  class ::Topic < ActiveRecord::Base
    validates :title, ease_check_text: true, unless: Proc.new { |v| v.new_record? }
  end

  class ::UploadsController < ApplicationController
    before_action :ease_check_image, only: %i[create]

    def ease_check_image
      url = params[:url]
      file = params[:file] || params[:files]&.first
      is_api = is_api?
      type =
        (params[:upload_type].presence || params[:type].presence).parameterize(separator: "_")[0..50]

      if current_user.admin?
        return
      end

      if file.nil?
        if url.present? && is_api
          maximum_upload_size = [
            SiteSetting.max_image_size_kb,
            SiteSetting.max_attachment_size_kb,
          ].max.kilobytes
          tempfile =
            begin
              FileHelper.download(
                url,
                follow_redirect: true,
                max_file_size: maximum_upload_size,
                tmp_file_name: "discourse-upload-#{type}",
              )
            rescue StandardError
              nil
            end
          filename = File.basename(URI.parse(url).path)
        end
      else
        tempfile = file.tempfile
        filename = file.original_filename
      end

      image_base64 = Base64.encode64(File.read(tempfile))
      suggestion, detail = "DiscourseEaseCheck::#{SiteSetting.easecheck_provider}".constantize.run_image_check(image_base64)
      if suggestion == "block" || suggestion == "review"
        render json: UploadsController.serialize_upload(
          { errors: [I18n.t("easecheck_contains_unallowed_image", detail: detail)]}), status: 422
      end
    end
  end
end
