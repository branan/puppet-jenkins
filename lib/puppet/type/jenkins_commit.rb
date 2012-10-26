module Puppet
  newtype(:jenkins_commit) do
    @doc = "This type is an implementation detail. DO NOT use it directly"
    newparam(:name) do
      isnamevar
    end

    newparam(:job) do
    end

    def commit
      @parameters[:job].value.provider.commit
    end
  end
end
