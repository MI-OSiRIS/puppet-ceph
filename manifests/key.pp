#
# Copyright (C) 2014 Catalyst IT Limited.
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
# Author: Ricardo Rocha <ricardo@catalyst.net.nz>
#
# Handles ceph keys (cephx), generates keys, creates keyring files, injects
# keys into or delete keys from the cluster/keyring via ceph and ceph-authtool
# tools.
#
# == Define: ceph::key
#
# If keyid not specified, the resource title is used as ceph ID name, e.g. 'client.admin' or 'mon.'.  
#
# === Parameters:
#
# [*secret*] Key secret.
#   Mandatory. Can be created with ceph-authtool --gen-print-key.
#
# [*cluster*] The ceph cluster
#   Optional. Defaults to 'ceph' 
#
# [*keyid*] ceph key ID such as 'client.admin'
#   Optional.  Defaults to resource title.
#
# [*keyring_path*] Path to the keyring file.
#   Optional. Absolute path to the keyring file, including the file name.
#   Defaults to /etc/ceph/${cluster}.${name}.keyring.
#
# [*cap_mon*] cephx capabilities for MON access.
#   Optional. e.g. 'allow *'
#   Defaults to 'undef'.
#
# [*cap_osd*] cephx capabilities for OSD access.
#   Optional. e.g. 'allow *'
#   Defaults to 'undef'.
#
# [*cap_mds*] cephx capabilities for MDS access.
#   Optional. e.g. 'allow *'
#   Defaults to 'undef'.
#
# [*user*] Owner of the *keyring_path* file.
#   Optional. Defaults to 'root'.
#
# [*group*] Group of the *keyring_path* file.
#   Optional. Defaults to 'root'.
#
# [*mode*] Mode (permissions) of the *keyring_path* file.
#   Optional. Defaults to 0600.
#
# [*inject*] True if the key should be injected into the cluster.
#   Optional. Boolean value (true to inject the key).
#   Default to false.
#
# [*inject_as_id*] the ceph ID used to inject the key Optional. Only
#   taken into account if 'inject' was set to true, in which case it
#   overrides the ceph default if set to a value other than
#   undef. Default to undef.
#
# [*inject_keyring*] keyring file with injection credentials
#   Optional. Only taken into account if 'inject' was set to true. If
#   set to a value other than undef, it overrides the ceph default
#   inferred from the client name. Default to undef.
#
define ceph::key (
  $secret,
  $ensure  = present,
  $cluster = undef,
  $keyid = "${name}",
  $keyring_path = undef,
  $cap_mon = undef,
  $cap_osd = undef,
  $cap_mds = undef,
  $cap_mgr = undef,
  $user = 'root',
  $group = 'root',
  $mode = '0600',
  $inject = false,
  $inject_as_id = undef,
  $inject_keyring = undef,
) {
  if ($cluster) {
    $cluster_option = "--cluster ${cluster}"
    $cluster_name = $cluster
  } else {
    $cluster_name = 'ceph'
  }
  if ! $keyring_path {
    $keyring_file = "/etc/ceph/${cluster_name}.${keyid}.keyring"
  } else {
    $keyring_file = $keyring_path
  }
  # cap_mon/cap_osd/cap_mds/cap_mgr are accepted for compatibility but not applied: this
  # define only writes the keyring file below. (A $caps string used to be built from them
  # and never used; it referenced unset variables and warned on every compile.)
  # this allows multiple defines for the same 'keyring file',
  # which is supported by ceph-authtool
  if ! defined(File[$keyring_file]) {
    file { $keyring_file:
      ensure  => $ensure,
      owner   => $user,
      group   => $group,
      mode    => $mode,
      require => Package['ceph-common'],
      content => "[${keyid}]
      key = $secret
",
      replace => false,
    }
  }
}
