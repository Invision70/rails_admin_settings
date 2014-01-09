require 'thread'

# we are inheriting from BasicObject so we don't get a bunch of methods from
# Kernel or Object
class Settings < BasicObject
  cattr_accessor :file_uploads_supported, :file_uploads_engine
  @@file_uploads_supported = false
  @@file_uploads_engine = false
  @@namespaces = {}
  @@mutex = ::Mutex.new

  class << self
    def ns(name, options = {})
      options.symbolize_keys!
      if name.nil?
        name = 'main'
      else
        name = name.to_s
      end
      @@mutex.synchronize do
        @@namespaces[name] ||= ::RailsAdminSettings::Namespaced.new(name.to_s)
      end
      if options[:fallback].nil?
        @@namespaces[name]
      else
        ::RailsAdminSettings::Fallback.new(@@namespaces[name], options[:fallback])
      end
    end

    def unload!
      @@mutex.synchronize do
        @@namespaces.values.map(&:unload!)
        @@namespaces = {}
      end
    end

    def destroy_all!
      RailsAdminSettings::Setting.destroy_all
      unload!
    end

    def root_file_path
      if Object.const_defined?('Rails')
        Rails.root
      else
        Pathname.new(File.dirname(__FILE__)).join('../..')
      end
    end

    def apply_defaults!(file)
      if File.file?(file)
        yaml = YAML.load(File.read(file), safe: true)
        yaml.each_pair do |namespace, vals|
          vals.symbolize_keys!
          n = ns(namespace)
          vals.each_pair do |key, val|
            val.symbolize_keys!
            if !val[:type].nil? && (val[:type] == 'file' || val[:type] == 'image')
              unless @@file_uploads_supported
                ::Kernel.raise ::RailsAdminSettings::PersistenceException, "Fatal: setting #{key} is #{val[:type]} but file upload engine is not detected"
              end
              value = File.open(root_file_path.join(val.delete(:value)))
            else
              value = val.delete(:value)
            end
            n.set(key, value, val.merge(overwrite: false))
          end
          n.unload!
        end
      end
    end

    def get(key, options = {})
      options.symbolize_keys!

      if options[:ns].nil? || options[:ns].to_s == 'main'
        ns('main').get(key, options)
      else
        ns(options[:ns]).get(key, options)
      end
    end

    def set(key, value = nil, options = {})
      options.symbolize_keys!

      if options[:ns].nil? || options[:ns].to_s == 'main'
        ns('main').set(key, value, options)
      else
        ns(options[:ns]).set(key, value, options)
      end
    end

    def save_default(key, value, options = {})
      set(key, value, options.merge(overwrite: false))
    end

    def create_setting(key, value, options = {})
      set(key, nil, options.merge(overwrite: false))
    end

    def method_missing(*args)
      ns('main').__send__(*args)
    end
  end
end

