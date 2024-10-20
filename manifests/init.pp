#   Copyright (C) 2013, 2014 iWeb Technologies Inc.
#   Copyright (C) 2013 Cloudwatt <libre.licensing@cloudwatt.com>
#   Copyright (C) 2014 Nine Internet Solutions AG
#   Copyright (C) 2014 Catalyst IT Limited
#   Copyright (C) 2015 Red Hat
#   
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#
# Author: Loic Dachary <loic@dachary.org>
# Author: Francois Charlier <francois.charlier@enovance.com>
# Author: David Moreau Simard <dmsimard@iweb.com>
# Author: Andrew Woodward <awoodward@mirantis.com>
# Author: David Gurtner <aldavud@crimson.ch>
# Author: Ricardo Rocha <ricardo@catalyst.net.nz>
# Author: Emilien Macchi <emilien@redhat.com>
#
# == Class: ceph::
#
# Install ceph packages.  Use ceph::cluster resource to define a cluster
#
# === Parameters:
#
# [*ensure*] The ensure state for package ressources.
#  Optional. Defaults to 'present'.
#
# [*release*] The name of the Ceph release to install
#   Optional. Default to 'hammer'.
#
# [*fastcgi*] Install Ceph fastcgi apache module for Ceph
#   Optional. Defaults to 'false'
#
# [*proxy*] Proxy URL to be used for the yum repository, useful if you're behind a corporate firewall
#   Optional. Defaults to 'undef'
#
# [*proxy_username*] The username to be used for the proxy if one should be required
#   Optional. Defaults to 'undef'
#
# [*proxy_password*] The password to be used for the proxy if one should be required
#   Optional. Defaults to 'undef'
#
# [*enable_epel*] Whether or not enable EPEL repository.
#   Optional. Defaults to True
#
# [*enable_sig*] Whether or not enable SIG repository.
#   CentOS SIG repository contains Ceph packages built by CentOS community.
#   https://wiki.centos.org/SpecialInterestGroup/Storage/
#   Optional. Defaults to False
#

class ceph (
  $ensure         = present,
  #$release        = 'jewel',
  $fastcgi        = false,
  $proxy          = undef,
  $proxy_username = undef,
  $proxy_password = undef,
  $enable_epel    = true,
  $enable_sig     = false,
) {

  include ::ceph::params
  
  # el7 repo does not contain ceph beyond octopus
  if versioncmp($facts['os']['release']['major'],'7') <= 0 {
        $release = 'octopus'
  } else {
        $release = 'reef'
  }

  # for use in version comparisons with < >
  $releasechar = join("${release}".match(/[a-z]/), "")

  package { $::ceph::params::packages :
    ensure => $ensure,
    tag    => 'ceph'
  }

  file { '/var/log/ceph':
    ensure => directory,
    owner => 'ceph',
    group => 'ceph',
    recurse => true,
    require => Package[$::ceph::params::packages]
  }

  if $ensure !~ /(absent|purged)/ {
    # Make sure ceph is installed before managing the configuration
    Package<| tag == 'ceph' |> -> Ceph_config<| |>
    # make sure packages create their associated subdirs before creating instance dirs (ie, /var/lib/ceph/mgr/instance)
    Package<| tag == 'ceph' |> -> File<| tag == 'ceph' |> 
    Package<| tag == 'ceph' |> -> Service<| tag == 'ceph' |>
    # File<| tag == 'ceph' |> -> Service<| tag == 'ceph' |>
  }

  case $::osfamily {
    'Debian': {
      include ::apt

      apt::key { 'ceph':
        ensure => $ensure,
        id     => '08B73419AC32B4E966C1A330E84AC2C0460F3994',
        source => 'https://download.ceph.com/keys/release.asc',
      }

      apt::source { 'ceph':
        ensure   => $ensure,
        location => "http://download.ceph.com/debian-${release}/",
        release  => $::lsbdistcodename,
        require  => Apt::Key['ceph'],
        tag      => 'ceph',
      }

      if $fastcgi {

        apt::key { 'ceph-gitbuilder':
          ensure => $ensure,
          id     => 'FCC5CB2ED8E6F6FB79D5B3316EAEAE2203C3951A',
          server => 'keyserver.ubuntu.com',
        }

        apt::source { 'ceph-fastcgi':
          ensure   => $ensure,
          location => "http://gitbuilder.ceph.com/libapache-mod-fastcgi-deb-${::lsbdistcodename}-${::hardwaremodel}-basic/ref/master",
          release  => $::lsbdistcodename,
          require  => Apt::Key['ceph-gitbuilder'],
        }

      }

      Apt::Source<| tag == 'ceph' |> -> Package<| tag == 'ceph' |>
      Exec['apt_update'] -> Package<| tag == 'ceph' |>
    }

    'RedHat': {
      $enabled = $ensure ? { 'present' => '1', 'absent' => '0', default => absent, }

      # If you want to deploy Ceph using packages provided by CentOS SIG
      # https://wiki.centos.org/SpecialInterestGroup/Storage/
      if $enable_sig {
        if $::operatingsystem != 'CentOS' {
          warning("CentOS SIG repository is only supported on CentOS operating system, not on ${::operatingsystem}, which can lead to packaging issues.")
        }
        exec { 'installing_centos-release-ceph':
          command   => '/usr/bin/yum install -y centos-release-ceph',
          logoutput => 'on_failure',
          tries     => 3,
          try_sleep => 1,
          unless    => '/usr/bin/rpm -qa | /usr/bin/grep -q centos-release-ceph',
        }
        # Make sure we install the repo before any Package resource
        Exec['installing_centos-release-ceph'] -> Package<| tag == 'ceph' |>
      } else {
        $el = $facts['os']['release']['major']
        
        Yumrepo {
          proxy          => $proxy,
          proxy_username => $proxy_username,
          proxy_password => $proxy_password,
        }

        if versioncmp($facts['os']['release']['major'],'8') <= 0 {
          yumrepo { 'ext-ceph':
            # puppet versions prior to 3.5 do not support ensure, use enabled instead
            enabled    => $enabled,
            descr      => "External Ceph ${release}",
            name       => "ext-ceph-${release}",
            baseurl    => "http://download.ceph.com/rpm-${release}/el${el}/\$basearch",
            gpgcheck   => '1',
            gpgkey     => 'https://download.ceph.com/keys/release.asc',
            mirrorlist => absent,
            priority   => '10', # prefer ceph repos over EPEL
            tag        => 'ceph',
          }

          yumrepo { 'ext-ceph-noarch':
            # puppet versions prior to 3.5 do not support ensure, use enabled instead
            enabled    => $enabled,
            descr      => 'External Ceph noarch',
            name       => "ext-ceph-${release}-noarch",
            baseurl    => "http://download.ceph.com/rpm-${release}/el${el}/noarch",
            gpgcheck   => '1',
            gpgkey     => 'https://download.ceph.com/keys/release.asc',
            mirrorlist => absent,
            priority   => '10', # prefer ceph repos over EPEL
            tag        => 'ceph',
          }
        } elsif versioncmp($facts['os']['release']['major'],'9') >= 0 {
          package { 'centos-release-ceph-reef': ensure => present }
        }

        if $fastcgi {
          yumrepo { 'ext-ceph-fastcgi':
            enabled    => $enabled,
            descr      => 'FastCGI basearch packages for Ceph',
            name       => 'ext-ceph-fastcgi',
            baseurl    => "http://gitbuilder.ceph.com/mod_fastcgi-rpm-rhel${el}-x86_64-basic/ref/master",
            gpgcheck   => '1',
            gpgkey     => 'https://download.ceph.com/keys/autobuild.asc',
            mirrorlist => absent,
            priority   => '20', # prefer ceph repos over EPEL
            tag        => 'ceph',
          }
        }

        if versioncmp($facts['os']['release']['major'],'7') == 0 {
          # prefer ceph.com repos over EPEL
          package { 'yum-plugin-priorities':
            ensure => present,
          }
        }
      }

      if $enable_epel {
        yumrepo { "ext-epel-${el}":
          # puppet versions prior to 3.5 do not support ensure, use enabled instead
          enabled    => $enabled,
          descr      => "External EPEL ${el}",
          name       => "ext-epel-${el}",
          baseurl    => absent,
          gpgcheck   => '1',
          gpgkey     => "https://dl.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-${el}",
          mirrorlist => "http://mirrors.fedoraproject.org/metalink?repo=epel-${el}&arch=\$basearch",
          priority   => '20', # prefer ceph repos over EPEL
          tag        => 'ceph',
          exclude    => 'python-ceph-compat python-rbd python-rados python-cephfs',
        }
      }

      Yumrepo<| tag == 'ceph' |> -> Package<| tag == 'ceph' |>
    }

    default: {
      fail("Unsupported osfamily: ${::osfamily} operatingsystem: ${::operatingsystem}, module ${module_name} only supports osfamily Debian and RedHat")
    }
  }
}
