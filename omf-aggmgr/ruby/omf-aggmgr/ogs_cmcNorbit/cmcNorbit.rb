#
# Copyright (c) 2006-2009 National ICT Australia (NICTA), Australia
#
# Copyright (c) 2004-2009 - WINLAB, Rutgers University, USA
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
# = cmcStub.rb
#
# == Description
#
# This file defines CmcStubService class.
#

require 'net/telnet'
require 'omf-aggmgr/ogs/gridService'

#
# This class defines the CMC (Chassis Manager Controller) Stub Service.
#
# A CMC Service normally provides information on the available nodes in a given
# testbed and basic functionality to switch them on and off.
# However, this particular CMC service is just a 'stub' that does not implement
# most CMC features, but instead answer 'OK' to most of the received requests.
# It is temporarily needed to allow the NodeHandler to run on the NICTA platform
# where the experimental nodes have currently no CM functionalities.
#
# For more details on how features of this Service are implemented below, please
# refer to the description of the AbstractService class
#
class CmcNorbitService < GridService

  # name used to register/mount the service, the service's url will be based on it
  name 'cmcn'
  description 'Power control for testbed nodes equipped with a CM2 card'
  @@config = nil

  #
  # Implement 'on' service using the 'service' method of AbstractService
  #
  # Note: Correct behaviour of 'on' is
  #       - if node is already ON do nothing
  #       - if node is OFF then turn it ON
  #
  s_description 'Switch ON a resource'
  s_param :hrn, 'hrn', 'hrn of the resource'
  s_param :domain, 'domain', 'domain for request.'  
  service 'on' do |hrn, domain|
    if !poweredOn?(hrn, domain)
      next powerToggle(hrn, domain) 
    else
      next true
    end
  end

  #
  # Implement 'offHard' service using the 'service' method of AbstractService
  #
  s_description 'Switch off a node (hard)'
  s_param :hrn, 'hrn', 'hrn of the resource'
  s_param :domain, 'domain', 'domain for request.'
  service 'offHard' do |hrn, domain|
    if poweredOn?(hrn, domain)
      next powerToggle(hrn, domain) 
    else
      next true
    end
  end
  
  #
  # Implement 'offSoft' service using the 'service' method of AbstractService
  #
  s_description 'Switch off a node (reboot, soft)'
  s_param :hrn, 'hrn', 'hrn of the resource'
  s_param :domain, 'domain', 'domain for request.'
  service 'offSoft' do |hrn, domain|
    reboot(hrn, domain)
  end

  #
  # Implement 'reboot' service using the 'service' method of AbstractService
  #
  # Soft reboot via telnet or SSH
  #
  s_description 'Reboot a resource (soft)'
  s_param :hrn, 'hrn', 'hrn of the resource'
  s_param :domain, 'domain', 'domain for request.'
  service 'reboot' do |hrn, domain|
    reboot(hrn, domain)
  end

  #
  # Implement 'reset' service using the 'service' method of AbstractService
  #
  # Note: Correct behaviour of 'reset' is
  #       - if node is already ON, then reset/reboot it
  #       - if node is OFF then turn it ON
  #
  s_description 'Reset a resource (hard)'
  s_param :hrn, 'hrn', 'hrn of the resource'
  s_param :domain, 'domain', 'domain for request.'
  service 'reset' do |hrn, domain|
    reset(hrn, domain)
  end

  #
  # Implement 'status' service using the 'service' method of AbstractService
  #
  # Return the power state of a given node
  #
  s_description 'Return the power state of a given node'
  s_param :hrn, 'hrn', 'hrn of the resource'
  s_param :domain, 'domain', 'domain for request.'
  service 'status' do |hrn, domain|
    root = REXML::Element.new('NODE_STATUS')
    detail = root.add_element('detail')
    state = poweredOn?(hrn, domain) ? 'POWERON' : 'POWEROFF'
    attr = {'hrn' => hrn, 'state' => "#{state}" }
    detail.add_element('node', attr)
    root
  end

  #
  # Configure the service through a hash of options
  #
  # - config = the Hash holding the config parameters for this service
  #
  def self.configure(config)
    @@config = config
  end

  def self.reboot(hrn, domain)
    MObject.debug("Sending REBOOT cmd to '#{hrn}'")
    ip = getCmcIP(hrn, domain)
    begin
      cmd = `nmap #{ip} -p22-23`
      #MObject.debug("TDEBUG - NMAP - '#{cmd}'")
      if cmd.include? "22/tcp open"
        ssh = `ssh -o CheckHostIP=no -o StrictHostKeyChecking=no #{ip} reboot`
      #MObject.debug("TDEBUG - SSH - '#{ssh}'")
      elsif cmd.include? "23/tcp open"
        tn = Net::Telnet::new('Host' => ip)
        tn.puts "root"
        tn.puts "reboot"
        tn.close
        #MObject.debug("TDEBUG - TELNET - '#{ssh}'")
      end
    rescue Exception => ex
      MObject.debug("CMCNORBIT - Failed to send REBOOT to '#{hrn}' at #{ip} - Exception: #{ex}")
    end
    true
  end
  
  def self.poweredOn?(hrn, domain)
    ip_port = getSwitchPort(hrn, domain).split(":")
    begin
      switch_ip = ip_port[0]
      switch_port = ip_port[1]
    rescue
      raise "CMCNORBIT - Failed to check power state of node '#{hrn}'"
    end
        
    switch_user = @@config['switch_user']
    switch_pw = @@config['switch_pw']

    tn = Net::Telnet::new('Host' => switch_ip, "Dump_log" => "/tmp/output_log_switch", "Prompt" => /[\>\#]/n)
    tn.cmd('String' => switch_user, 'Match' => /Password:/n)
    tn.cmd(switch_pw)
    tn.cmd('String' => "enable", 'Match' => /Password:/n)
    tn.cmd(switch_pw)
    state = tn.cmd("show port 0/#{switch_port}")
    if state.include? "Up"
      MObject.debug("Node '#{hrn}' is powered on.")
      powered = true
    elsif state.include? "Down"
      MObject.debug("Node '#{hrn}' is powered down.")
      powered = false
    else
      MObject.debug("Error checking power state of node '#{hrn}'.")
      powered = nil
    end
    tn.puts("logout") # use puts, don't wait for prompt as cmd does
    tn.close
    raise "CMCNORBIT - Failed to check power state of node '#{hrn}'" if powered.nil?
    powered
  end
  
  def self.powerToggle(hrn, domain)
    tn = openTelnet(hrn, domain)
    tn.puts "pcpwr"
    closeTelnet(tn)
    true
  end

  def self.reset(hrn, domain)
    tn = openTelnet(hrn, domain)
    tn.puts "pcres"
    closeTelnet(tn)
    true
  end

  def self.openTelnet(hrn, domain)
    ip = getCmcIP(hrn, domain)
    tn = Net::Telnet::new('Host' => ip, "Dump_log" => "/tmp/output_log")
    tn.waitfor("Prompt" => /CM2\> /n)
    return tn
  end

  def self.closeTelnet(tn)
    tn.puts "exit"
    tn.close
  end
  
  #
  # Configure the service through a hash of options
  #
  # - config = the Hash holding the config parameters for this service
  #
  def self.configure(config)
    @@config = config
  end
  
end
