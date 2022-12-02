### discourse-sensitive-easecheck

This plugin allows to perform texts or images sensitive check when users create posts 
or update them.

This is mainly based on the service of Huawei Cloud Moderation. If you want to use other 
provider's sensitive check services, you'd better edit the request format in plugin.rb.

## Usage 

# Part1: Clone

First, clone this repository to 'plugins' directory:

'git clone https://gitee.com/opensourceway/EaseCheck.git'

or add above command to 'web_only.yml' if using discourse docker.

# Part2: Configuration

Second, configure service parameters:

'sensitive_enabled' - enable plugin

'sensitive_text_check_url' - your provider's text check url

'sensitive_image_check_url' - your provider's image check url

'sensitive_project_id' - the project id from your provider 

'sensitive_project_name' - the project name from your provider

'sensitive_json_suggestion_path' - suggestion path in response, i.e. result.suggestion

'sensitive_json_hits_path' - hit words path in text check response, i.e. result.segments

'sensitive_auth_url' - your provider's authorization url to get token

'sensitive_json_token_path' - the token path in auth response

'sensitive_expire_time' - how long token is valid/ hour, i.e. 23

'sensitive_debug_info' - if log debug info about sensitive easecheck, logs can be viewed at admins/log

# Part3: Access validator

The original forum only opens the processing interface for creating new posts. So, in order to validate 
the plugin, you need to add validator to topic/post's model for text check and upload controlller for 
image check.

In models/topic.rb, add topic validator:

'validates :title, title_moderator: {unless: Proc.new { |v| v.new_record? }}'

In models/post.rb, add post validator:

'validates :raw, post_moderator: true, unless: Proc.new { |v| v.new_record? }'

In controllers/upload_controller.rb, add in line 266:
'image_base64 = Base64.encode64(File.read(tempfile))'
'suggestion = ::Moderator.should_block_image? image_base64, 'article', ['all']'
'if suggestion == 'block''
'    return { errors: [I18n.t("contains_sensitive_image")] }'
'end'


For more information, please see: **https://www.huaweicloud.com/product/moderation.html**
