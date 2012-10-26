module Puppet
  newtype(:jenkins_scm) do
    ensurable do
      defaultvalues
      defaultto :present
    end

    newparam(:name) do
      isnamevar
    end

    newproperty(:repo) do
      desc "The git repo which should be checked out by Jenkins"
    end

    newparam(:job) do
      desc "The Jenkins_job to which this scm checkout belongs. Must be a resource reference."
      validate do |value|
        raise ArgumentError, "#{value} is not a resource reference" unless value.is_a? Puppet::Resource
      end
    end
  end
end
