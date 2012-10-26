require 'nokogiri'
require 'open-uri'
require 'net/http'

Puppet::Type.type(:jenkins_job).provide(:xml, :parent => Puppet::Provider) do
  mk_resource_methods

  def exists?
    unless @property_hash[:ensure].nil?
      return @property_hash[:ensure] == :present
    end

    return false
  end

  def create
    builder = Nokogiri::XML::Builder.new do |xml|
      project = proc {
        xml.actions
        xml.description
        xml.logRotator {
          xml.daysToKeep '24'
          xml.numToKeep '60'
          xml.artifactDaysToKeep '-1'
          xml.artifactNumToKeep '-1'
        }
        xml.scm :class => 'hudson.scm.NullSCM'
        xml.keepDependencies 'false'
        xml.properties
        xml.canRoam 'true'
        xml.disabled @resource[:disable].to_s
        xml.blockBuildWhenDownstreamBuilding 'false'
        xml.blockBuildWhenUpstreamBuilding 'false'
        xml.triggers :class => 'vector'
        xml.concurrentBuild @resource[:concurrent].to_s
        xml.axes
        xml.builders
        xml.publishers
        xml.buildWrappers {
          if @resource[:colorize] == :true
            colorMapName = proc {
              xml.colorMapName 'xterm'
            }
            xml.send 'hudson.plugins.ansicolor.AnsiColorBuildWrapper'.intern, :plugin=>'ansicolor', &colorMapName
          end
        }
        xml.executionStrategy(:class => 'hudson.matrix.DefaultMatrixExecutionStrategyImpl') {
          xml.runSequentially 'false'
        }
      }
      xml.send 'matrix-project'.intern, &project
    end
    @property_hash = {
      :job_xml    => builder.doc,
      :create_job => true,
      :name       => @resource[:name]
    }
  end

  def colorize=(value)
    if value == :true
      Nokogiri::XML::Builder.with(@property_hash[:job_xml].css('buildWrappers')[0]) do |xml|
        colorMapName = proc {
          xml.colorMapName 'xterm'
        }
        xml.send 'hudson.plugins.ansicolor.AnsiColorBuildWrapper'.intern, :plugin=>'ansicolor', &colorMapName
      end
    else
      buildWrappers = @property_hash[:job_xml].css('buildWrappers')[0]
      buildWrappers.children.each do |child|
        child.remove if child.name == 'hudson.plugins.ansicolor.AnsiColorBuildWrapper'
      end
    end
  end

  def concurrent=(value)
    @property_hash[:job_xml].css('concurrentBuild')[0].content = value.to_s
  end

  def disable=(value)
    @property_hash[:job_xml].css('disabled')[0].content = value.to_s
  end

  def commit
    xml_blob = @property_hash[:job_xml].serialize
    if @property_hash[:create_job]
      job_uri = URI.escape("http://jenkins-enterprise.acctest.dc1.puppetlabs.net/createItem?name=#{@property_hash[:name]}")
      url = URI.parse(job_uri)
      request = Net::HTTP::Post.new("#{url.path}?#{url.query}") 
      request['Content-Type'] = 'text/xml'
      request.body = xml_blob
      response = Net::HTTP.start(url.host, url.port) { |http| http.request(request) }
    else
      url = URI.parse(@property_hash[:job_uri])
      request = Net::HTTP::Post.new(url.path)
      request.body = xml_blob
      response = Net::HTTP.start(url.host, url.port) { |http| http.request(request) }
    end
    #TODO error check the response
  end

  def self.prefetch(resources)
    instances(resources).each do |instance|
      if job = resources[instance.name]
        job.provider = instance
      end
    end
  end

  def self.instances(resources=nil)
    servers = {}
    instances = []

    if resources
      resources.each_value do |res|
        if res[:server]
          servers[res[:server]] = {}
          #TODO support authentication
        end
      end
    else
      if Facter["jenkins_username"]
        servers[Facter["jenkins_server"].value()] = {
          :username => Facter["jenkins_username"].value(),
          :password => Facter["jenkins_password"].value()
        }
      else
        servers[Facter["jenkins_server"].value()] = {}
      end
    end
    servers.each do |server, creds|
      username = creds[:username]
      password = creds[:password]
      options = {}
      options[:http_basic_authentication] = [username, password] if username
      jenkins_main = Nokogiri::XML(open("http://#{server}/api/xml", options))
      jenkins_main.css('job').map do |job|
        job_uri = job.css('url').text + "/config.xml"
        job_config = Nokogiri::XML(open(job_uri, options))
        params = {
          :ensure   => :present,
          :provider => :xml,
          :job_xml  => job_config,
          :job_uri  => job_uri,
          :name     => job.css('name').text,
          :server   => server,
          :username => username,
          :password => password
        }
        instances << new(params.merge parse_xml(job_config))
      end
    end
    instances
  end

  def self.parse_xml(document)
    result = { }

    result[:concurrent] = document.css('concurrentBuild').text.to_sym
    result[:colorize] = document.css('colorMapName').empty? ? :false : :true
    result[:disable] = document.css('disabled')[0].text.to_sym

    result
  end

  def get_section(selector)
    elems = @property_hash[:job_xml].css(selector)
    if elems.empty?
      raise "dammit, we can't create sections yet"
    else
      elems[0]
    end
  end
end
