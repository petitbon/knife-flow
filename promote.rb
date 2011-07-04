require 'chef/knife'
 
module ChefFlow
  class Promote < Chef::Knife
 
    deps do
      require 'chef/cookbook_loader'
      require 'chef/cookbook_uploader'
      require 'chef/environment'
      require 'chef/knife/core/object_loader'
    end
 
    banner "knife promote ENVIRONMENT COOKBOOK"
 
    WORKING_BRANCH = "develop"
    
    def run


      all_args = parse_name_args!
      env_name = all_args[0]
      all_args.shift
      cookbooks = all_args
      
      self.config = Chef::Config.merge!(config)
      
      switch_org(env_name)

      self.config = Chef::Config.merge!(config)
     
      if !config[:cookbook_path]
        raise ArgumentError, "Default cookbook_path is not specified in the knife.rb config file, and a value to -o is not provided. Nowhere to write the new cookbook to." 
      end
      @cookbook_path = Array(config[:cookbook_path]).first
      

      if check_branch(WORKING_BRANCH)
        
        # 0) make sure we have the latest from the working branch
        pull_branch(WORKING_BRANCH)

        env_json = load_env_file(env_name)
        
        env_data = JSON.parse(env_json)
    

        cookbooks.each do | book |
          metadata_file = File.join(@cookbook_path, book, "metadata.rb")

          # 1) increase version on the metadata file
          replace_version(find_version(book), increment_version(find_version(book)), metadata_file )
      
          # 2) merge the new cookbook into the environment
          env_data.cookbook_versions.merge!(book => find_version(book))
        
        end
        
        # 3) write the environment to file
        File.open("environments/#{env_name}.json","w") do |f|
          f.write(JSON.pretty_generate(env_data))
        end
        
        # 4) upload cookbooks to chef server
        Chef::Knife::CookbookUpload.new(cookbooks).run
        
        # 5) upload environment to chef server
        knife_environment_from_file = Chef::Knife::EnvironmentFromFile.new
        knife_environment_from_file.name_args = ["#{env_name}.json"]
        output = knife_environment_from_file.run

        # 6) commit and push all changes to develop 
        commit_and_push_branch(WORKING_BRANCH, "#{cookbooks.join(" and ").to_s} have been promoted to the #{env_name} environment")

      end

    end
  
    def switch_org(env_name)
      # TODO: someone smarter than me can switch the organization without requiring 2 different knife.rb files
      current_dir = File.dirname(__FILE__)   
      case env_name
      when "production"
        Chef::Config[:config_file] = "#{current_dir}/../../knife-production.rb"
      when "candidate"
        Chef::Config[:config_file] = "#{current_dir}/../../knife.rb"
      end
      ::File::open(config[:config_file]) { |f| apply_config(f.path) }
    end

    def load_env_file(env_name)
      if File.exist?("environments/#{env_name}.json")
        File.read("environments/#{env_name}.json")
      else
        # TODO: we should handle the creation of the environment.json file if it doesn't exist.
        raise ArgumentError, "environments/#{env_name}.json was not found; please create the environment file manually.#{env_name}"
      end
    end

    def apply_config(config_file_path)
      Chef::Config.from_file(config_file_path)
      Chef::Config.merge!(config)
    end

    def commit_and_push_branch(branch, comment)
      print "--------------------------------- \n"
      system("git pull origin #{branch}") 
      system("git add .")
      system("git commit -am  '#{comment}'")
      system("git push origin #{branch}")
      print "--------------------------------- \n"
    end

    def pull_branch(name)
      print "--------------------------------- \n"
      system("git pull origin #{name}")
      print "--------------------------------- \n"
    end

    def check_branch(name)
      if (`git status` =~ /#{name}/) != nil
        return true
      else
        ui.error("USAGE: you must be in the #{name} branch to promote cookbooks")
        exit 1
      end
    end

    def parse_name_args!
      if name_args.empty?
        ui.error("USAGE: knife promote ENVIRONMENT COOKBOOK COOKBOOK ...")
        exit 1
      else
        return name_args
      end
    end

    def find_version(name)
     loader = Chef::CookbookLoader.new(@cookbook_path)
     return loader[name].version
    end

    def increment_version(version)
     current_version = version.split(".").map{|i| i.to_i}
     current_version[2] = current_version[2] + 1
     return current_version.join('.')
    end

    def replace_version(search_string, replace_string, file)
      open_file = File.open(file, "r")
      body_of_file = open_file.read
      open_file.close
      body_of_file.gsub!(search_string, replace_string)
      File.open(file, "w") { |file| file << body_of_file }
    end


  end
end