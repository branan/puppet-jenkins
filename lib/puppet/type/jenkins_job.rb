module Puppet
  newtype(:jenkins_job) do
    newparam(:name) do
      isnamevar
    end

    ensurable do
      defaultvalues
      defaultto :present
    end

    newproperty(:concurrent) do
      desc "If set to true, Jenkins will allow multiple instances of this job to run in parallel. Defaults to false."
      defaultto :false
      newvalues(:true, :false)
    end

    newproperty(:colorize) do
      desc "If set to true, ANSI color codes will be converted to HTML in the jenkins job output. Requires the AnsiColor plugin. Defaults to false."
      defaultto :false
      newvalues(:true, :false)
    end

    newproperty(:disable) do
      desc "If set to true, this job will not be executed by Jenkins. Defaults to false."
      defaultto :false
      newvalues(:true, :false)
    end

    newparam(:server) do
      desc "The Jenkins server on which this job should be created"
    end

    # Keep your arms and legs inside the vehicle at all times, it's
    # time for a bit of a ride.
    #
    # In order to allow parts of a jenkins job to be split into their
    # own resources, a particular series of events needs to happen.
    #
    # 1. The main job resource must be applied. This will either
    #    create or fetch the jenkins configuration data, which all the
    #    other resources will need.
    # 2. All the components need to be applied. They will modify the
    #    job configuration stored in the main job resource.
    # 3. This final jenkins configuration is pushed to the Jenkins
    #    server.
    #
    # Using this ordering also buys us a really cool feature for free:
    # If any component of a job fails, none of the changes to that job
    # will be pushed to Jenkins. That is to say, jenkins job changes
    # are atomic in this model.
    #
    # The first two steps can be handled through normal Puppet
    # resource ordering, although there are some bits of "special" to
    # them - see the autorequire function below for the information
    # there.
    #
    # Step 3 is tough, since the Jenkins_job resource can't be in two
    # places at once. We solves this by auto-generating a special
    # Jenkins_commit resource here. Its ordering is managed by the
    # autorequire function.
    def generate
      options = { :name => @title, :job => self }
      @flusher = Puppet::Type.type(:jenkins_commit).new(options)
      [ @flusher ]
    end

    # The normal puppet autorequire system does not allow for
    # notifies. This method re-implements autorequires with notifies
    # enabled. Using notifies allows us to ensure that the
    # Jenkins_commit object is only run if the job (or one of its
    # components) is changed.
    #
    # We use a simple heuristic to determine which resources to insert
    # into the graph at this point:
    #
    # * The resource must have a 'job' parameter
    # * That parameter must be a resource reference
    # * That reference must point to this Jenkins_job instane
    def autorequire(rel_catalog = nil)
      rel_catalog ||= catalog
      raise(Puppet::DevError, "You cannot add relationship without a catalog") unless rel_catalog

      reqs = super
      rel_catalog.resources.each do |res|
        job = res.parameters[:job]
        next unless job
        next unless job.value.is_a? Puppet::Resource

        if job.value.title == @parameters[:name].value and job.value.type == "Jenkins_job"
          reqs << Puppet::Relationship.new(self, res)
          reqs << Puppet::Relationship.new(res, @flusher, {:event => :ALL_EVENTS, :callback => :commit })
        end
      end
      reqs << Puppet::Relationship.new(self, @flusher, {:event => :ALL_EVENTS, :callback => :commit })

      reqs
    end
  end
end
