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

  # package { $::ceph::params::packages :
  #   ensure => $ensure,
  #   tag    => 'ceph'
  # }

  file { '/var/log/ceph':
    ensure => directory,
    owner => 'ceph',
    group => 'ceph',
    # require => Package[$::ceph::params::packages],
    recurse => true,
    # Don't enforce SELinux contexts: cephadm labels /var/log/ceph/<fsid> container_file_t, and
    # resetting it to ceph_log_t on every recursive run made Puppet and cephadm relabel in a loop.
    selinux_ignore_defaults => true,
  }

  # if $ensure !~ /(absent|purged)/ {
  #   # Make sure ceph is installed before managing the configuration
  #   Package<| tag == 'ceph' |> -> Ceph_config<| |>
  #   # make sure packages create their associated subdirs before creating instance dirs (ie, /var/lib/ceph/mgr/instance)
  #   Package<| tag == 'ceph' |> -> File<| tag == 'ceph' |> 
  #   Package<| tag == 'ceph' |> -> Service<| tag == 'ceph' |>
  #   # File<| tag == 'ceph' |> -> Service<| tag == 'ceph' |>
  # }

  case $facts['os']['family'] {
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
        release  => $facts.dig('os', 'distro', 'codename'),
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
          location => "http://gitbuilder.ceph.com/libapache-mod-fastcgi-deb-${facts['os']['distro']['codename']}-${facts['os']['hardware']}-basic/ref/master",
          release  => $facts.dig('os', 'distro', 'codename'),
          require  => Apt::Key['ceph-gitbuilder'],
        }

      }

      Apt::Source<| tag == 'ceph' |> -> Package<| tag == 'ceph' |>
      Exec['apt_update'] -> Package<| tag == 'ceph' |>
    }

    'RedHat': {
    }

    default: {
      fail("Unsupported osfamily: ${facts['os']['family']} operatingsystem: ${facts['os']['name']}, module ${module_name} only supports osfamily Debian and RedHat")
    }
  }
}
