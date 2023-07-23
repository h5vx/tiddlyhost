#
# Read settings from config/settings.yml and config/settings_local.yml
#
class Settings

  # Used to avoid throwing errors if build-info.txt is not there
  PLACEHOLDER_BUILD_INFO = {
    "date" => "Wed May 4 12:41:58 PM EDT 2022",
    "sha" => "0123456789abcdef",
    "build_number" => 42,
    "commit" => "Fix stuff",
    "branch" => "devel",
  }

  SETTINGS = begin
    # Since we might run this before Rails has started
    rails_root = "#{__dir__}/.."
    rails_env = ENV['RAILS_ENV'] || 'development'

    # If we're running in /opt/app then assume it's in the container
    # (Used in settings.yaml to tweak db name, url protocol and port)
    is_in_container = File.expand_path(rails_root) == "/opt/app"

    read_settings = ->(settings_file) do
      file_name = "#{rails_root}/#{settings_file}"
      return nil unless File.exist?(file_name)
      erb_template = ERB.new(File.read(file_name))
      settings_yaml = erb_template.result_with_hash(is_in_container: is_in_container)
      YAML.load(settings_yaml) || {}
    end

    settings = read_settings["config/settings.yml"]
    settings_local = read_settings["config/settings_local.yml"]
    build_info = {"build_info" =>
      (read_settings["public/build-info.txt"] || PLACEHOLDER_BUILD_INFO)}

    settings['defaults'].merge(settings[rails_env]).merge(build_info).merge(settings_local)
  end

  def self.method_missing(method)
    SETTINGS[method.to_s]
  end

  def self.secrets(*dig_args)
    Rails.application.credentials.dig(*dig_args)
  end

  def self.main_site_host
    Settings.url_defaults[:host]
  end

  def self.main_site_url
    ActionDispatch::Http::URL.full_url_for(Settings.url_defaults)
  end

  # This is the same as `new_user_session_path` but we'll hard code it here
  def self.login_url
    "#{main_site_url}/users/sign_in"
  end

  def self.tiddlyspot_enabled?
    Rails.env.test? || Settings.secrets(:dreamobjects).present?
  end

  def self.tiddlyspot_url_defaults
    Settings.url_defaults.merge(host: Settings.tiddlyspot_host, protocol: 'http')
  end

  def self.tiddlyspot_url
    ActionDispatch::Http::URL.full_url_for(tiddlyspot_url_defaults)
  end

  def self.subdomain_site_host(site_name)
    "#{site_name}.#{Settings.main_site_host}"
  end

  def self.subdomain_site_url(site_name)
    ActionDispatch::Http::URL.full_url_for(Settings.url_defaults.merge(subdomain: site_name))
  end

  def self.tiddlyspot_site_host(site_name)
    "#{site_name}.#{Settings.tiddlyspot_host}"
  end

  def self.tiddlyspot_site_url(site_name)
    ActionDispatch::Http::URL.full_url_for(tiddlyspot_url_defaults.merge(subdomain: site_name))
  end

  def self.force_ssl
    self.url_defaults[:protocol] == 'https'
  end

  def self.short_sha(length=7)
    self.build_info["sha"][0...length]
  end

  def self.app_version
    "#{major_version}.#{build_info["build_number"]}-#{Settings.short_sha}"
  end

  def self.feature_enabled?(feature_name, user)
    # A way to grant access to particular users manually
    if user
      grant_list = Settings.secrets(:grant_feature, feature_name.to_sym)
      return true if grant_list&.include?(user.id) || grant_list&.include?(user.email)
    end

    # Otherwise use methods defined in lib/settings/features
    enabled_method_name = "#{feature_name}_enabled?"
    !!(Settings::Features.respond_to?(enabled_method_name) && Settings::Features.send(enabled_method_name, user))
  end

  def self.feature_list
    ([:free] + Settings::Features.methods(false).map{|m| m.to_s.sub(/_enabled\?/, '').to_sym}).uniq.sort
  end

  def self.stripe_products
    Settings.secrets(Rails.env.to_sym, :stripe, :products)
  end

  # The OpenStruct should have keys :name, :price, :id
  def self.stripe_product(plan, frequency=:monthly)
    OpenStruct.new(self.stripe_products&.dig(plan, frequency))
  end

  # Look up a product's details from its stripe id
  def self.stripe_product_by_id(plan_id)
    OpenStruct.new(stripe_products&.values.map(&:values).flatten.find{|p| p[:id] == plan_id})
  end

end
