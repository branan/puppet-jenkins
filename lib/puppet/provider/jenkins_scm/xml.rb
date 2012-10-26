Puppet::Type.type(:jenkins_scm).provide(:xml, :parent => Puppet::Provider) do
  mk_resource_methods

  def exists?
    unless @property_hash[:ensure].nil?
      return @property_hash[:ensure] == :present
    end

    false
  end
  
  def create
    @property_hash[:create_job] = true
    @property_hash[:name] = @resource[:name]
    @property_hash[:scm_xml] = @resource.catalog.resources.select { |res|
      res.class == Puppet::Type::Jenkins_job && res.title == @resource[:job].title
    }[0].provider.get_section('scm')
 
    Nokogiri::XML::Builder.with(@property_hash[:scm_xml]) do |xml|
      xml.configVersion '2'
      xml.userRemoteConfigs {
        remote = proc {
          xml.name
          xml.refspec
          xml.url @resource[:repo]
        }
        xml.send 'hudson.plugins.git.UserRemoteConfig'.intern, &remote
      }
      xml.branches {
        branch = proc {
          xml.name 'origin/master'
        }
        xml.send 'hudson.plugins.git.BranchSpec'.intern, &branch
      }
      xml.disableSubmodules 'false'
      xml.recursiveSubmodules 'false'
      xml.doGenerateSubmoduleConfigurations 'false'
      xml.authorOrComitter 'false'
      xml.clean 'false'
      xml.wipeOutWorkspace 'false'
      xml.pruneBranches 'false'
      xml.remotePoll 'false'
      xml.ignoreNotifyCommit 'false'
      xml.useShallowClone 'false'
      xml.buildChooser :class => 'hudson.plugins.git.util.DefaultBuildChooser'
      xml.gitTool 'Default'
      xml.submoduleCfg :class => 'list'
      xml.relativeTargetDir
      xml.reference
      xml.excludeRegions
      xml.excludedUsers
      xml.gitConfigName
      xml.gitConfigEmail
      xml.skipTag 'false'
      xml.includedRegions
      xml.scmName
    end

    @property_hash[:scm_xml]['class'] = 'hudson.plugins.git.GitSCM'
    @property_hash[:scm_xml]['plugin'] = 'git'
  end

  def flush
    return if @property_hash[:create_job]

    scm_xml = @property_hash[:scm_xml]
    url_element = scm_xml.css('userRemoteConfigs url')[0]
    url_element.content = @property_hash[:repo]
  end

  def self.prefetch(resources)
    catalog = resources.values[0].catalog
    instances(catalog).each do |instance|
      resources.each_pair do |name, resource|
        raise "Must specify the job that this instance belongs to" unless resource[:job]
        if resource[:job].title == instance.job.title
          resource.provider = instance
        end
      end
    end
  end

  def self.instances(catalog = nil)
    instances = []

    if catalog
      catalog_resources = catalog.resources.select do |res|
        res.class == Puppet::Type::Jenkins_job
      end
      catalog_resources.each do |job|
        scm_info = job.provider.get_section('scm')
        url_element = scm_info.css('userRemoteConfigs url')
        if url_element and not url_element.text.empty?
          instances << new(:name => "#{url_element.text} <#{job.title}>", :repo => url_element.text, :ensure => :present, :provider => :xml, :job => job, :scm_xml => scm_info)
        end
      end
    else
      # If we aren't given a catalog as an argument, this is probably
      # a 'puppet resource' run. Let's get ALL THE JOBS and find their
      # scm bits We don't bother setting the job in this case. That
      # will trigger failures later on (using jenkins_scm without
      # puppetizing the job is not allowed) and it's not printed by
      # puppet resource anyway.
      Puppet::Type.type(:jenkins_job).defaultprovider.instances.each do |job|
        scm_info = job.get_section('scm')
        url_element = scm_info.css('userRemoteConfigs url')
        if url_element and not url_element.text.empty?
          instances << new(:name => "#{url_element.text} <#{job.name}>", :repo => url_element.text, :ensure => :present, :provider => :xml, :scm_xml => scm_info)
        end
      end
    end
    instances
  end
end
