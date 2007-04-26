<!---
License:
Copyright 2007 Mach-II Corporation

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

Copyright: Mach-II Corporation
Author: Peter J. Farrell (peter@mach-ii.com)
$Id$

Created version: 1.0.0
Updated version: 1.5.0

Notes:
- Added introspection to call only defined plugin points. (dross, pfarrell, hklein)
- Fixed metadata introspection bug with components that have no fuctions (pfarrell)
--->
<cfcomponent 
	displayname="PluginManager"
	output="false"
	hint="Manages registered Plugins for the framework instance.">
	
	<!---
	PROPERTIES
	--->
	<cfset variables.appManager = "" />
	<cfset variables.plugins = StructNew() />
	<cfset variables.pluginArray = ArrayNew(1) />
	<cfset variables.pluginArrayPosition = StructNew() />
	<cfset variables.preProcessPlugins = ArrayNew(1) />
	<cfset variables.preProcessPluginsPosition = StructNew() />
	<cfset variables.preEventPlugins = ArrayNew(1) />
	<cfset variables.preEventPluginsPosition = StructNew() />
	<cfset variables.postEventPlugins = ArrayNew(1) />
	<cfset variables.postEventPluginsPosition = StructNew() />
	<cfset variables.preViewPlugins = ArrayNew(1) />
	<cfset variables.preViewPluginsPosition = StructNew() />
	<cfset variables.postViewPlugins = ArrayNew(1) />
	<cfset variables.postViewPluginsPosition = StructNew() />
	<cfset variables.postProcessPlugins = ArrayNew(1) />
	<cfset variables.postProcessPluginsPosition = StructNew() />
	<cfset variables.handleExceptionPlugins = ArrayNew(1) />
	<cfset variables.handleExceptionPluginsPosition = StructNew() />
	<cfset variables.nPlugins = 0 />
	<cfset variables.parentPluginManager = "" />
	<cfset variables.utils = "" />
	<cfset variables.pluginPointArray = ListToArray("preProcess,preEvent,postEvent,preView,postView,postProcess,handleException") />
	
	<!---
	INITIALIZATION / CONFIGURATION
	--->
	<cffunction name="init" access="public" returntype="PluginManager" output="false"
		hint="Initialization function called by the framework.">
		<cfargument name="appManager" type="MachII.framework.AppManager" required="true" />
		<cfargument name="parentPluginManager" type="any" required="false" default=""
			hint="Optional argument for a parent plugin manager. If there isn't one default to empty string." />
		
		<cfset setAppManager(arguments.appManager) />
		<cfset variables.utils = getAppManager().getUtils() />
		
		<cfif isObject(arguments.parentPluginManager)>
			<cfset setParent(arguments.parentPluginManager) />
		</cfif>
		
		<cfreturn this />
	</cffunction>
	
	<cffunction name="loadXml" access="public" returntype="void" output="false"
		hint="Loads xml into the manager.">
		<cfargument name="configXML" type="string" required="true" />
		<cfargument name="override" type="boolean" required="false" default="false" />
		
		<cfset var pluginNodes = 0 />
		<cfset var paramNodes = 0 />
		<cfset var paramName = 0 />
		<cfset var paramValue = 0 />
		<cfset var plugin = 0 />
		<cfset var pluginName = 0 />
		<cfset var pluginType = 0 />
		<cfset var pluginParams = 0 />
		<cfset var i = 0 />
		<cfset var j = 0 />
		
		<!--- Scoped argument variable - configXML --->
		<cfif NOT arguments.override>
			<cfset pluginNodes = XMLSearch(arguments.configXML, "mach-ii/plugins/plugin") />
		<cfelse>
			<cfset pluginNodes = XMLSearch(arguments.configXML, ".//plugins/plugin") />
		</cfif>
		<cfloop index="i" from="1" to="#ArrayLen(pluginNodes)#">
			<cfset pluginName = pluginNodes[i].XmlAttributes["name"] />
			<cfset pluginType = pluginNodes[i].XmlAttributes["type"] />

			<!--- Set the Plugin's parameters. --->
			<cfset pluginParams = StructNew() />
			
			<!--- For each plugin, parse all the parameters --->
			<cfif StructKeyExists(pluginNodes[i], "parameters")>
				<cfset paramNodes = pluginNodes[i].parameters.xmlChildren />
				<cfloop from="1" to="#ArrayLen(paramNodes)#" index="j">
					<cfset paramName = paramNodes[j].XmlAttributes["name"] />
					<cfset paramValue = variables.utils.recurseComplexValues(paramNodes[j]) />				
					<cfset pluginParams[paramName] = paramValue />
				</cfloop>
			</cfif>
			
			<cfset plugin = CreateObject("component", pluginType).init(getAppManager(), pluginParams) />
			<cfset addPlugin(pluginName, plugin, arguments.override) />
		</cfloop>
	</cffunction>
	
	<cffunction name="configure" access="public" returntype="void"
		hint="Configures each of the registered Plugins.">
		<cfset var aPlugin = 0 />
		<cfset var i = 0 />
		
		<cfloop from="1" to="#variables.nPlugins#" index="i">
			<cfset aPlugin = variables.pluginArray[i] />
			<cfset aPlugin.configure() />
		</cfloop>
	</cffunction>
	
	<!---
	PUBLIC FUNCTIONS
	--->
	<cffunction name="getPlugin" access="public" returntype="MachII.framework.Plugin" output="false"
		hint="Gets a plugin with the specified name.">
		<cfargument name="pluginName" type="string" required="true" />
		
		<cfif isPluginDefined(arguments.pluginName)>
			<cfreturn variables.plugins[arguments.pluginName] />
		<cfelseif isObject(getParent()) AND getParent().isPluginDefined(arguments.pluginName)>
			<cfreturn getParent().getPlugin(arguments.pluginName) />
		<cfelse>
			<cfthrow type="MachII.framework.PluginNotDefined" 
				message="Plugin with name '#arguments.pluginName#' is not defined." />
		</cfif>
	</cffunction>
	
	<cffunction name="addPlugin" access="public" returntype="void" output="false"
		hint="Registers a plugin with the specified name.">
		<cfargument name="pluginName" type="string" required="true" />
		<cfargument name="plugin" type="MachII.framework.Plugin" required="true" />
		<cfargument name="override" type="boolean" required="false" default="false" />
		
		<cfset var i = 0 />
		<cfset var pointName = 0 />
		<cfset var temp = "" />
		<cfset var pluginRegisteredPoints = ListToArray(findPluginPoints(arguments.plugin)) />		

		<cfif NOT arguments.override AND isPluginDefined(arguments.pluginName)>
			<cfthrow type="MachII.framework.PluginAlreadyDefined"
				message="A Plugin with name '#arguments.pluginName#' is already registered." />
		<cfelseif arguments.override AND isPluginDefined(arguments.pluginName)>
			<cfset variables.plugins[arguments.pluginName] = arguments.plugin />
			<cfset variables.pluginArray[variables.pluginArrayPosition[arguments.pluginName]] = arguments.plugin />
			
			<!--- re-add references to this plugin for each registered point --->
			<cfloop from="1" to="#ArrayLen(pluginRegisteredPoints)#" index="i">
				<cfset pointName = pluginRegisteredPoints[i] />
				<cfif StructKeyExists(variables, pointName & "Plugins")>
					<cfif StructKeyExists(variables[pointName & "PluginsPosition"], arguments.pluginName)>
						<cfset variables[pointName & "Plugins"][variables[pointName & "PluginsPosition"][arguments.pluginName]] = arguments.plugin />
					<cfelse>
						<cfset ArrayInsertAt(variables[pointName & "Plugins"], variables.pluginArrayPosition[arguments.pluginName], arguments.plugin) />
					</cfif>
					<cfset temp = ListAppend(temp, pointName) />
				</cfif>
			</cfloop>

			<!--- delete any references from the old plugin for each registered point not in new plugin --->
			<cfloop from="1" to="#ArrayLen(variables.pluginPointArray)#" index="i">
				<cfset pointName = variables.pluginPointArray[i] />
				<cfif StructKeyExists(variables[pointName & "PluginsPosition"], arguments.pluginName) AND NOT ListFindNoCase(temp, pointName)>
					<cfset ArrayDeleteAt(variables[pointName & "Plugins"], variables.pluginArrayPosition[arguments.pluginName]) />
					<cfset StructDelete(variables[pointName & "PluginsPosition"], arguments.pluginName) />
				</cfif>
			</cfloop>
			
			<cfdump var="#temp#">
			<cfdump var="#variables#">
			
			<cfabort>
		<cfelse>
			<cfset variables.plugins[arguments.pluginName] = arguments.plugin />
			
			<cfset variables.nPlugins = variables.nPlugins + 1 />
			<cfset variables.pluginArray[variables.nPlugins] = arguments.plugin />
			<cfset variables.pluginArrayPosition[arguments.pluginName] = variables.nPlugins />
			
			<!--- add references to this plugin for each registered point --->
			<cfloop from="1" to="#ArrayLen(pluginRegisteredPoints)#" index="i">
				<cfset pointName = pluginRegisteredPoints[i] />
				<cfif StructKeyExists(variables, pointName & "Plugins")>
					<cfset ArrayAppend(variables[pointName & "Plugins"], arguments.plugin) />
					<cfset variables[pointName & "PluginsPosition"][arguments.pluginName] = ArrayLen(variables[pointName & "Plugins"])>
				</cfif>
			</cfloop>
		</cfif>
	</cffunction>
	
	<cffunction name="isPluginDefined" access="public" returntype="boolean" output="false"
		hint="Returns true if a Plugin is registered with the specified name.">
		<cfargument name="pluginName" type="string" required="true" />
		<cfreturn StructKeyExists(variables.plugins, arguments.pluginName) />
	</cffunction>
	
	<cffunction name="getPluginNames" access="public" returntype="array" output="false"
		hint="Returns an array of plugin names.">
		<cfreturn StructKeyArray(variables.plugins) />
	</cffunction>
	
	<!---
	PLUGIN POINT FUNCTIONS
	--->
	<cffunction name="preProcess" access="public" returntype="void" output="true"
		hint="preProcess() is called for each new EventContext once before event processing begins.">
		<cfargument name="eventContext" type="MachII.framework.EventContext" required="true" 
			hint="The EventContext of the processing." />
		
		<cfset var i = 0 />
		
		<cfloop from="1" to="#ArrayLen(variables.preProcessPlugins)#" index="i">
			<cfset variables.preProcessPlugins[i].preProcess(arguments.eventContext) />
		</cfloop>
		
		<cfif isObject(getParent())>
			<cfset getParent().preProcess(arguments.eventContext) />
		</cfif>
	</cffunction>
	
	<cffunction name="preEvent" access="public" returntype="void" output="true"
		hint="preEvent() is called for each announced Event before it is handled.">
		<cfargument name="eventContext" type="MachII.framework.EventContext" required="true"
			hint="The EventContext the Event occurred in. Call arguments.eventContext.getCurrentEvent() to access the Event." />
		
		<cfset var i = 0 />
		
		<cfloop from="1" to="#ArrayLen(variables.preEventPlugins)#" index="i">
			<cfset variables.preEventPlugins[i].preEvent(arguments.eventContext) />
		</cfloop>
		
		<cfif isObject(getParent())>
			<cfset getParent().preEvent(arguments.eventContext) />
		</cfif>
	</cffunction>

	<cffunction name="postEvent" access="public" returntype="void" output="true"
		hint="postEvent() is called for each announced Event after it has been handled.">
		<cfargument name="eventContext" type="MachII.framework.EventContext" required="true"
			hint="The EventContext the Event occurred in. Call arguments.eventContext.getCurrentEvent() to access the Event." />
		
		<cfset var i = 0 />
		
		<cfloop from="1" to="#ArrayLen(variables.postEventPlugins)#" index="i">
			<cfset variables.postEventPlugins[i].postEvent(arguments.eventContext) />
		</cfloop>
		
		<cfif isObject(getParent())>
			<cfset getParent().postEvent(arguments.eventContext) />
		</cfif>
	</cffunction>
	
	<cffunction name="preView" access="public" returntype="void" output="true"
		hint="preView() is called for each announced Event after it has been handled.">
		<cfargument name="eventContext" type="MachII.framework.EventContext" required="true"
			hint="The EventContext of the processing." />
		
		<cfset var i = 0 />
		
		<cfloop from="1" to="#ArrayLen(variables.preViewPlugins)#" index="i">
			<cfset variables.preViewPlugins[i].preView(arguments.eventContext) />
		</cfloop>
		
		<cfif isObject(getParent())>
			<cfset getParent().preView(arguments.eventContext) />
		</cfif>
	</cffunction>

	<cffunction name="postView" access="public" returntype="void" output="true"
		hint="postView() is called for each announced Event after it has been handled.">
		<cfargument name="eventContext" type="MachII.framework.EventContext" required="true"
			hint="The EventContext of the processing." />
		
		<cfset var i = 0 />
		
		<cfloop from="1" to="#ArrayLen(variables.postViewPlugins)#" index="i">
			<cfset variables.postViewPlugins[i].postView(arguments.eventContext) />
		</cfloop>
		
		<cfif isObject(getParent())>
			<cfset getParent().postView(arguments.eventContext) />
		</cfif>
	</cffunction>

	<cffunction name="postProcess" access="public" returntype="void" output="true"
		hint="postProcess() is called for each new EventContext once after event processing completes.">
		<cfargument name="eventContext" type="MachII.framework.EventContext" required="true" 
			hint="The EventContext of the processing." />
		
		<cfset var i = 0 />
		
		<cfloop from="1" to="#ArrayLen(variables.postProcessPlugins)#" index="i">
			<cfset variables.postProcessPlugins[i].postProcess(arguments.eventContext) />
		</cfloop>
		
		<cfif isObject(getParent())>
			<cfset getParent().postProcess(arguments.eventContext) />
		</cfif>
	</cffunction>

	<cffunction name="handleException" access="public" returntype="void" output="true"
		hint="handleException() is called for each exception caught by the framework.">
		<cfargument name="eventContext" type="MachII.framework.EventContext" required="true"
			hint="The EventContext under which the exception was thrown/caught." />
		<cfargument name="exception" type="MachII.util.Exception" required="true"
			hint="The Exception object." />
		
		<cfset var i = 0 />
		
		<cfloop from="1" to="#ArrayLen(variables.handleExceptionPlugins)#" index="i">
			<cfset variables.handleExceptionPlugins[i].handleException(arguments.eventContext, arguments.exception) />
		</cfloop>
		
		<cfif isObject(getParent())>
			<cfset getParent().handleException(arguments.eventContext, arguments.exception) />
		</cfif>
	</cffunction>

	<!---
	PROTECTED FUNCTIONS
	--->
	<cffunction name="findPluginPoints" access="private" returntype="string" output="false"
		hint="Finds the registered plugin points in a plugin.">
		<cfargument name="plugin" type="MachII.framework.Plugin" required="true" />		
		
		<cfset var md = GetMetaData(arguments.plugin) />
		<cfset var pointArray = ArrayNew(1) />
		<cfset var returnList = "" />
		<cfset var i = 0 />
				
		<!--- recursively search the plugin's parents for plugin points --->
		<cfset pointArray = gatherPluginMetaData(md, pointArray) />
		
		<!--- Make sure there are functions to transverse --->
		<cfif StructKeyExists(md, "functions")>
			<!--- then pull function names defined in this plugin --->
			<cfloop from="1" to="#ArrayLen(md.functions)#" index="i">
				<cfset ArrayAppend(pointArray, md.functions[i].name) />
			</cfloop>
			
			<!--- remove duplicates --->
			<cfloop from="1" to="#ArrayLen(pointArray)#" index="i">
				<cfif not ListFindNoCase(returnList, pointArray[i])>
					<cfset returnList = ListAppend(returnList, pointArray[i]) />
				</cfif>
			</cfloop>
		</cfif>
		
		<cfreturn returnList />	
	</cffunction>
	
	<cffunction name="gatherPluginMetaData" access="private" returntype="array" output="false"
		hint="Gathers meta data about a plugin.">
		<cfargument name="metadata" type="struct" required="true" />
		<cfargument name="points" type="array" required="true" />
		
		<cfset var i = 0 />

		<cfif StructKeyExists(arguments.metadata, "extends") and arguments.metadata.extends.name neq "MachII.framework.Plugin">
			<!--- Make sure there are function to transverse --->
			<cfif StructKeyExists(arguments.metadata.extends, "fuctions")>
				<cfloop from="1" to="#ArrayLen(arguments.metadata.extends.functions)#" index="i">
					<cfset ArrayAppend(arguments.points, arguments.metadata.extends.functions[i].name) />
				</cfloop>
			</cfif>
			<cfset gatherPluginMetaData(arguments.metadata.extends, arguments.points) />
		</cfif>
		
	    <cfreturn arguments.points />		
	</cffunction>

	<!---
	ACCESSORS
	--->
	<cffunction name="setAppManager" access="public" returntype="void" output="false"
		hint="Sets the AppManager instance this PluginManager belongs to.">
		<cfargument name="appManager" type="MachII.framework.AppManager" required="true" />
		<cfset variables.appManager = arguments.appManager />
	</cffunction>
	<cffunction name="getAppManager" access="public" returntype="MachII.framework.AppManager" output="false"
		hint="Returns the AppManager instance this PluginManager belongs to.">
		<cfreturn variables.appManager />
	</cffunction>
	
	<cffunction name="setParent" access="public" returntype="void" output="false"
		hint="Returns the parent PluginManager instance this PluginManager belongs to.">
		<cfargument name="parentPluginManager" type="MachII.framework.PluginManager" required="true" />
		<cfset variables.parentPluginManager = arguments.parentPluginManager />
	</cffunction>
	<cffunction name="getParent" access="public" returntype="any" output="false"
		hint="Sets the parent PluginManager instance this PluginManager belongs to. It will return empty string if no parent is defined.">
		<cfreturn variables.parentPluginManager />
	</cffunction>
	
</cfcomponent>