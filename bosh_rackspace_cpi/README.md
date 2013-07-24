# BOSH Rackspace Cloud Provider Interface
# Copyright (c) 2013 GoPivotal, Inc.

For online documentation see: http://rubydoc.info/gems/bosh_rackspace_cpi/

## Options

These options are passed to the Rackspace CPI when it is instantiated.

### Rackspace CPI options

The registry options are passed to the Rackspace CPI by the BOSH director based on the settings in `director.yml`:

<table>
  <tr>
    <th>Option</th>
    <th>Required</th>
    <th>Description</th>
  </tr>
  <tr>
    <td>username</td>
    <td>Y</td>
    <td>Rackspace Username</td>
  </tr>
  <tr>
    <td>api_key</td>
    <td>Y</td>
    <td>Rackspace API key</td>
  </tr>
  <tr>
    <td>region</td>
    <td>N</td>
    <td>Rackspace region (by default DFW)</td>
  </tr>
  <tr>
    <td>auth_url</td>
    <td>N</td>
    <td>Rackspace authorization endpoint</td>
  </tr>
  <tr>
    <td>connection_options</td>
    <td>N</td>
    <td>Optional connection parameters (see supported options at https://github.com/fog/fog/blob/master/lib/fog/rackspace/docs/compute_v2.md#optional-connection-parameters)</td>
  </tr>
</table>

### BOSH Registry options

The BOSH Registry options are passed to the Rackspace CPI by the BOSH director based on the settings in `director.yml`.

<table>
  <tr>
    <th>Option</th>
    <th>Required</th>
    <th>Description</th>
  </tr>
  <tr>
    <td>endpoint</td>
    <td>Y</td>
    <td>BOSH Registry URL</td>
  </tr>
  <tr>
    <td>user</td>
    <td>Y</td>
    <td>BOSH Registry user</td>
  </tr>
  <tr>
    <td>password</td>
    <td>Y</td>
    <td>BOSH Registry password</td>
  </tr>
</table>

### Agent options

The BOSH Agent options are passed to the Rackspace CPI by the BOSH director based on the settings in `director.yml`.

## BOSH Network options

The Rackspace CPI supports these networks types:

<table>
  <tr>
    <th>Type</th>
    <th>Description</th>
  </tr>
  <tr>
    <td>dynamic</td>
    <td>DHCP assigned IP by Rackspace</td>
  </tr>
</table>

These options are specified under `cloud_properties` in the `networks` section of a BOSH deployment manifest:

<table>
  <tr>
    <th>Option</th>
    <th>Required</th>
    <th>Description</th>
  </tr>
  <tr>
    <td>network_ids</td>
    <td>N</td>
    <td>Networks to be attached to Rackspace servers. If you do not specify any networks, the Rackspace server will be
    attached to the `public Internet' and `private ServiceNet' networks. If you specify one or more networks,
    the Rackspace server will be attached to only the networks that you specify, so if you want to attach to the
    `public Internet' and/or `private ServiceNet' networks, you must specify them explicitly:
    The UUID for the `public Internet' is 00000000-0000-0000-0000-000000000000
    The UUID for the`private ServiceNet' is 11111111-1111-1111-1111-111111111111</td>
  </tr>
</table>

## Resource pool options

These options are specified under `cloud_properties` in the `resource_pools` section of a BOSH deployment manifest:

<table>
  <tr>
    <th>Option</th>
    <th>Required</th>
    <th>Description</th>
  </tr>
  <tr>
    <td>instance_type</td>
    <td>Y</td>
    <td>which type of instance (Rackspace flavor) the VMs should belong to</td>
  </tr>
  <tr>
    <td>public_key</td>
    <td>N</td>
    <td>OpenSSH public key to be injected at the VMs, if not set, then to access to VMs must be via password</td>
  </tr>
</table>

## Example

This is a sample of how Rackspace specific properties are used in a BOSH deployment manifest:

    ---
    name: sample
    director_uuid: 38ce80c3-e9e9-4aac-ba61-97c676631b91

    ...

    networks:
      - name: default
        type: dynamic
        dns:
          - 8.8.8.8
          - 8.8.4.4
        cloud_properties:
          network_ids:
            - 00000000-0000-0000-0000-000000000000
            - 11111111-1111-1111-1111-111111111111
    ...

    resource_pools:
      - name: common
        network: default
        size: 1
        stemcell:
          name: bosh-stemcell
          version: latest
        cloud_properties:
          instance_type: '1GB Standard Instance'
          public_key: |
            ssh-rsa ...

    ...

    properties:
      rackspace:
        username: johnny
        api_key: QRoqsenPsNGX6