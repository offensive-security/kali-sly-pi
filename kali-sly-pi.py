#!/usr/bin/python
# This script is a modification of https://github.com/Xtrato/Slypi

from socket import socket, SOCK_DGRAM, AF_INET
import string
import os
import sys
from time import sleep
from Adafruit_CharLCDPlate import Adafruit_CharLCDPlate
import subprocess
import urllib #Used to display the Public IP address.
from subprocess import PIPE
from datetime import datetime # Used the genreate the filename used in the packet capture dump

# Initialize the LCD plate.  Should auto-detect correct I2C bus.  If not,
# pass '0' for early 256 MB Model B boards or '1' for all later versions
lcd = Adafruit_CharLCDPlate(busnum = 1)
# The following are the modules which can be added the SlyPi Device.
# To add the module simply define the function below and then add the module name and function name to the modules dictonary.
# All code the module executes is to be placed in the function.

def commandDone():
    lcd.clear()
    lcd.message("Done!\nPress Select")

def wifiHospotStart():
    print "Starting Wifi"
    wifiStart = subprocess.Popen('service hostapd start', shell=True, stderr=PIPE)
    error = wifiStart.communicate()
    errorCheck(error, 'Cannot start\nhostapd', 'Starting hostapd')
    print error

    print "Starting dnsmasq"
    dnsStart = subprocess.Popen('service dnsmasq start', shell=True, stderr=PIPE)
    error = dnsStart.communicate()
    errorCheck(error, 'Cannot start\ndnsmasq', 'Starting dnsmasq')
    print error

    print "Enabling NAT"
    iptableStart = subprocess.Popen('nat-start', shell=True, stderr=PIPE)
    error = iptableStart.communicate()
    errorCheck(error, 'Cannot enable\nNAT', 'Enabling NAT')
    print error
    commandDone()

def openVPNStart():
    print "Starting OpenVPN"
    openvpnStart = subprocess.Popen('service openvpn start', shell=True, stderr=PIPE)
    error = openvpnStart.communicate()
    errorCheck(error, 'Cannot start\nopenvpn', 'Starting openvpn')
    print error
    commandDone()

def wan3GStart():
    print "Starting 3G"
    wan3GStart = subprocess.Popen('wvdial wan &', shell=True, stderr=PIPE)
    error = wan3GStart.communicate()
    errorCheck(error, 'Cannot start\n3G', 'Starting 3G')
    print error
    commandDone()

def openVPNStop():
    print "Stopping OpenVPN"
    openvpnStop = subprocess.Popen('service openvpn stop', shell=True, stderr=PIPE)
    error = openvpnStop.communicate()
    errorCheck(error, 'Cannot stop\nopenvpn', 'Stopping openvpn')
    print error
    commandDone()

def wifiHospotStop():
    print "Stopping Wifi"
    wifiStop = subprocess.Popen('service hostapd stop', shell=True, stderr=PIPE)
    error = wifiStop.communicate()
    errorCheck(error, 'Cannot stop\nhostapd', 'Stopping hostapd')
    print error

    print "Stopping dnsmasq"
    dnsStop = subprocess.Popen('service dnsmasq stop', shell=True, stderr=PIPE)
    error = dnsStop.communicate()
    errorCheck(error, 'Cannot stop\ndnsmasq', 'Stopping dnsmasq')
    print error

    print "Stopping NAT"
    iptableStop = subprocess.Popen('nat-stop', shell=True, stderr=PIPE)
    error = iptableStop.communicate()
    errorCheck(error, 'Cannot disable\nNAT', 'Disabling NAT')
    print error
    commandDone()

def shutDown():
    print 'Shutting Down'
    lcd.clear()
    shutDown = subprocess.Popen('halt', shell=True, stdout=PIPE, stderr=PIPE)
    sys.exit(0)
    
def connectivityTest():
    print 'Connectivity Test'
    #Pings google.com
    thePing = subprocess.Popen('ping -c 5 google.com', shell=True, stdout=PIPE, stderr=PIPE)
    lcd.clear()
    lcd.backlight(lcd.GREEN)
    lcd.message("Testing\nConnectivity")
    pingOut, pingErr = thePing.communicate()
    #If the ping fails ping 8.8.8.8
    lcd.clear()
    if len(pingErr) > 0:
        lcd.backlight(lcd.RED)
        thePing = subprocess.Popen('ping -c 5 8.8.8.8', shell=True, stdout=PIPE, stderr=PIPE)
        pingOut, pingErr = thePing.communicate()
        print 1
        #If pinging 8.8.8.8 fails display there is no internet connection
        if len(pingErr) > 0:
            lcd.message("No Internet\nConnection")
            print 2
        #If pinging 8.8.8.8 succeeds, display there is no DHCP service available for the SlyPi to use.
        else:
            lcd.message("No DHCP\n Available")
            print 3
    else:
        privateIP = getPrivateIP()
        publicIP = getPublicIP()
        lcd.backlight(lcd.YELLOW)
        print privateIP
        print publicIP
        #Displays the public and private IP addresses on the LED screen.
        lcd.message(privateIP + '\n' + publicIP)
        sleep(3)
        funtionBreak()

def funtionBreak():
    while lcd.buttonPressed(lcd.LEFT):
        os.execl('kali-sly-pi.py', '')

def errorCheck(error, failedMessage, succeedMessage):
    lcd.clear()
    if 'brctl: not found' in error:
        lcd.backlight(lcd.RED)
        lcd.message("Failed\nInstall brctl")
    elif len(error[1]) == 0:
        lcd.backlight(lcd.GREEN)
        lcd.message(succeedMessage)
        sleep(3)
    elif len(error[1]) > 0:
        lcd.backlight(lcd.RED)
        lcd.message(failedMessage)
        sleep(2)
        os.execl('kali-sly-pi.py', '')
    error = 0

def getPublicIP():
    publicIPUrl = urllib.urlopen("http://my-ip.heroku.com/")
    return publicIPUrl.read()
    commandDone()

def getPrivateIP():
    s = socket(AF_INET, SOCK_DGRAM)
    s.connect(('google.com', 0))
    privateIp = s.getsockname()
    return privateIp[0]

#Contains all modules which can be run on the device. The key is the displayed name on the LCD and the value is the function name
# 3 4 2 1 5 7 6
modules = {
'Start OpenVPN': 'openVPNStart',
'Stop OpenVPN' : 'openVPNStop',
'Start Wifi AP': 'wifiHospotStart',
'Stop Wifi AP' : 'wifiHospotStop',
'Start 3G Net' : '3GStart',
'Network Test' : 'connectivityTest',
'Shutdown Kali': 'shutDown'
}

displayText = modules.keys()
# Clears the display
lcd.clear()
# Checks if the script has been run as root.
menuOption = 0
#lcd.backlight(lcd.BLUE)
lcd.message("Kali Linux\nPress Select")

#The following while loop controls the LCD menu and the control using the keypad through the menu.
while True:
    if lcd.buttonPressed(lcd.SELECT):
        sleep(0.5)
        lcd.clear()
        lcd.message(displayText[menuOption])
        while True:
            lcd.backlight(lcd.BLUE)
            if lcd.buttonPressed(lcd.DOWN):
                menuOption = menuOption + 1
                if menuOption > len(modules) - 1:
                    menuOption = 0
                lcd.clear()
                lcd.message(displayText[menuOption])
                sleep(0.5)
            if lcd.buttonPressed(lcd.UP):
                menuOption = menuOption - 1
                if menuOption < 0:
                    menuOption = len(modules) - 1
                lcd.clear()
                lcd.message(displayText[menuOption])
                sleep(0.5)
            if lcd.buttonPressed(lcd.SELECT):
                globals().get(modules[displayText[menuOption]])()
                sleep(0.5)
                break
            if lcd.buttonPressed(lcd.LEFT):
                print "left"
                menuOption = 0
                break
