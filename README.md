### discourse-easecheck

This plugin allows to perform texts or images content check when users create posts 
or update them.

This is mainly based on the service of HuaweiCloud Moderation service. If you want to use other 
provider's content check services, you need add service implements.

## Usage 

# Part1: Clone

First, clone this repository to 'plugins' directory:

'git clone https://gitee.com/opensourceway/discourse-easecheck.git'

or add above command to 'web_only.yml' if using discourse docker.

# Part2: Configuration

Second, configure service parameters:

'easecheck_enabled' - enable plugin

'easecheck_huaweicloud_text_check_endpoint' - huaweicloud's text check url

'easecheck_huaweicloud_image_check_endpoint' - huaweicloud's image check url

'easecheck_huaweicloud_project_id' - the project id of huaweicloud 

'easecheck_huaweicloud_project_name' - the project name of huaweicloud

'easecheck_huaweicloud_auth_token_endpoint' - huaweicloud's authorization url to get token

'easecheck_huaweicloud_token_validity_period' - how long token is valid/ hour, i.e. 23

'easecheck_huaweicloud_text_check_categories' - huaweicloud's categories included in text check request

'easecheck_huaweicloud_image_check_categories' - huaweicloud's categories included in image check request

'easecheck_provider' - your content check cloud service provider

'easecheck_debug_info' - if log debug info about easecheck easecheck, logs can be viewed at admins/log


For more information about HuaweiCloud Moderation service, please see: **https://www.huaweicloud.com/product/moderation.html**
