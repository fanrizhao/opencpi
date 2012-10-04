
/*
 *  Copyright (c) Mercury Federal Systems, Inc., Arlington VA., 2009-2010
 *
 *    Mercury Federal Systems, Incorporated
 *    1901 South Bell Street
 *    Suite 402
 *    Arlington, Virginia 22202
 *    United States of America
 *    Telephone 703-413-0781
 *    FAX 703-413-0784
 *
 *  This file is part of OpenCPI (www.opencpi.org).
 *     ____                   __________   ____
 *    / __ \____  ___  ____  / ____/ __ \ /  _/ ____  _________ _
 *   / / / / __ \/ _ \/ __ \/ /   / /_/ / / /  / __ \/ ___/ __ `/
 *  / /_/ / /_/ /  __/ / / / /___/ ____/_/ / _/ /_/ / /  / /_/ /
 *  \____/ .___/\___/_/ /_/\____/_/    /___/(_)____/_/   \__, /
 *      /_/                                             /____/
 *
 *  OpenCPI is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU Lesser General Public License as published
 *  by the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  OpenCPI is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU Lesser General Public License for more details.
 *
 *  You should have received a copy of the GNU Lesser General Public License
 *  along with OpenCPI.  If not, see <http://www.gnu.org/licenses/>.
 */
#include "OcpiOsMisc.h"
#include "OcpiUtilValue.h"
#include "OcpiPValue.h"
#include "OcpiApplication.h"
#include "OcpiTimeEmit.h"

namespace OC = OCPI::Container;
namespace OU = OCPI::Util;
namespace OL = OCPI::Library;
namespace OA = OCPI::API;
namespace OCPI {
  namespace API {
    ApplicationI::ApplicationI(const char *file, const PValue * policy)
      : m_assembly(*new OL::Assembly(file))  {
      init(policy);
    }
    ApplicationI::ApplicationI(const std::string &string, const PValue * policy)
      : m_assembly(*new OL::Assembly(string))  {
      init(policy);
    }
    ApplicationI::ApplicationI(OL::Assembly &assy, const PValue * policy)
      : m_assembly(assy) {
      m_assembly++;
      init(policy);
    }
    ApplicationI::~ApplicationI() {
      m_assembly--;
      if (m_containerApps) {
	for (unsigned n = 0; n < m_nContainers; n++)
	  delete m_containerApps[n];
	delete [] m_containerApps;
      }
      delete [] m_workers;
      delete [] m_usedContainers;
      delete [] m_instances;
      delete [] m_containers;
      delete [] m_properties;
    }

    void 
    ApplicationI::
    policyMap( Instance * i, CMap & bestMap, CMap & /* alliMap */)
    {

      // bestMap is a bitmap of the best availabe containers that the implementation can be mapped to
      // alliMap is the bitmap of all suitable containers for the implementation
      switch ( m_cMapPolicy ) {

      case MaxProcessors:
	{  // If we are here the policy is a "limited to" m_procesors policy

	  // First figure out if we have already hit our limit
	  if (  m_nContainers >= m_processors ) {
	    for ( unsigned n=0; n<m_nContainers; n++ ) {
	      if ( m_currConn >= m_nContainers ) m_currConn=0;
	      CMap map = 1<<m_usedContainers[m_currConn++];
	      if ( map & bestMap ) {
		i->m_container = m_currConn-1;
		return;
	      }
	    }
	  }
	}
	// Not at our limit, let RR find the next available
	
      case RoundRobin:
	{
	  // Now we must select the container for the best candidate.
	  // As a default, we will rotate through the possible containers to spread them out
	  // So, find the next (rotating) container for the best candidate
	  CMap map;
	  do {
	    if (++m_currConn >= OC::Container::maxContainer)
	      m_currConn = 0;
	    map = 1 << m_currConn;
	  } while (!(map & bestMap));
	  ocpiDebug("map %d best %d curr %d", map, bestMap, m_currConn);
	  if (!(m_allMap & map)) {
	    // A container we have not used yet.
	    m_allMap |= map;
	    i->m_container = m_nContainers;
	    // Note we save the container ordinal, not the container pointer,
	    // simply to allow the container to go away after this API (construction)
	    // and before the next (initialize).  At least we can check for errors.
	    m_usedContainers[m_nContainers++] = m_currConn;

	  } 
	  else {
	    for (unsigned c = 0; c < m_nContainers; c++) {
	      if (m_usedContainers[c] == m_currConn) {
		i->m_container = c;
		break;
	      }
	    }
	  }

	}
	break;

      case MinProcessors:
	{
	  if ( m_processors == 0 ) {  // Special case, we use the minimum possible
	    CMap map=1;
	    for ( unsigned n=0; n<OC::Container::maxContainer; n++, map=1<<n ) {
	      if ( map & bestMap ) {
		m_currConn = n;
		break;
	      }
	    }
	    if ( ! (map&bestMap) ) {
	      throw std::string("No Suitable container found for worker");
	    }
	    std::cout << map << " " << bestMap << " " << m_currConn << std::endl;	
	    if (!(m_allMap & map)) {
	      m_allMap |= map;
	      i->m_container = m_nContainers;
	      m_usedContainers[m_nContainers++] = m_currConn;
	    }
	    else {
	      for (unsigned c = 0; c < m_nContainers; c++) {
		if (m_usedContainers[c] == m_currConn) {
		  i->m_container = c;
		  break;
		}
	      }
	    }
	  }
	}
	break;
      }
    }

    // Possible override the original policy in the xml
    void ApplicationI::
    setPolicy(const PValue *params) {
      uint32_t pcount;
      bool rr;
      if (OU::findULong(params, "MaxProcessors", pcount)) {
	m_cMapPolicy = MaxProcessors;
	m_processors = pcount;
      } else if (OU::findULong(params, "MinProcessors", pcount)) {
	m_cMapPolicy = MinProcessors;
	m_processors = pcount;
      } else if (OU::findBool(params, "RoundRobin", rr) && rr) {
	m_cMapPolicy = RoundRobin;
	m_processors = 0;
      }
    }
  

    void 
    ApplicationI::
    init( const PValue * policy ) {

      m_allMap = m_curMap = 0;   // accumulate all containers actually used
      m_nContainers = 0;
      m_containers = NULL;
      m_containerApps = NULL;
      m_workers = NULL;
      m_externalPorts = NULL;
      m_externalNames = NULL;
      m_properties = NULL;
      m_nProperties = 0;
      m_currConn = OC::Container::maxContainer - 1;
      m_cMapPolicy = RoundRobin;
      m_doneWorker = NULL;
      // Set the instance map policy
      setPolicy( policy );

      unsigned
	nInstances = m_assembly.m_instances.size();
      m_usedContainers = new unsigned[nInstances]; // over allocated - could use less
      // Application's instances
      Instance *i = m_instances = new Instance[nInstances];
      for (unsigned n = 0; n < nInstances; n++, i++)
	i->m_nCandidates = m_assembly.m_candidates[n].size();
      i = m_instances;
      // For all instances in the assembly (this loop is "backed up" sometimes)
      for (unsigned n = 0; n < nInstances; n++, i++) {
	OL::Candidates &cs = m_assembly.m_candidates[n];
	CMap
	  sum = 0,     // accumulate possible containers over candidates
	  bestMap = 0; // save map of best candidate.  initialized to kill warning
	unsigned bestScore = 0;
	bool nonReusable = false;     // remember if we ran out of containers
	unsigned backup = nInstances; // where to backup to if we run into a dead end
	// For all candidate implementations known to be suitable for this instance,
	// find the "best" one, filtering out those that are infeasible due to
	// constraints between implementations and containers etc. that could not
	// be ruled out earlier
	for (unsigned m = 0; m < cs.size(); m++) {
	  if (i->m_rejectedCandidates & (1 << m))
	    continue;
	  OL::Candidate &c = cs[m];
	  m_curMap = 0;        // to accumulate containers suitable for this candidate
	  m_curContainers = 0; // to count suitable containers for this candidate
	  (void)OC::Manager::findContainers(*this, cs[m].impl->m_metadataImpl);
	  if (!m_curMap)
	    continue; // if there are no containers that can run it, skip it
	  if (c.impl->m_instance) {
	    // Avoid implementations that are non-reusable if we don't have enough
	    // containers to use them all
	    unsigned nn, nContainers = 0; // How many containers are we already using
	    unsigned first = nInstances;  // Remember first potential con
	    for (nn = 0; nn < n; nn++)
	      if (c.impl == m_instances[nn].m_impl) {
		if (m_instances[nn].m_nCandidates > 1)
		  first = nn;
		if (++nContainers >= m_curContainers)
		  break;
	      }
	    if (nn < n) {
	      nonReusable = true;
	      if (first < backup)
		backup = first;
	      ocpiDebug("Skipping candidate due to container overflow");
	      continue;
	    }
	  }
	  // Check to see if this implementation is incompatible with previous choices.
	  // If it has any ports that are preconnected to instances that have already chosen
	  // incompatible implementations, skip it.
	  unsigned nPorts = c.impl->m_metadataImpl.nPorts();
	  bool skip = false;
	  // For all ports on this instance, check for incompatibility
	  for (unsigned nn = 0; nn < nPorts; nn++) {
	    OU::Assembly::Port *ap = m_assembly.assyPort(n, nn);
	    if ( ap) ocpiDebug("ap %p %p inst %u n %u nn %u", ap, ap->m_connectedPort,
		      ap->m_connectedPort ? ap->m_connectedPort->m_instance : 0, n, nn);
	    if(ap && ap->m_connectedPort && ap->m_connectedPort->m_instance < n &&
	       m_assembly.checkConnection(*c.impl, *m_instances[ap->m_connectedPort->m_instance].m_impl,
					  *ap, nn)) {
	      // Remember the earliest instance we might back up to if we have no solution
	      if (ap->m_connectedPort->m_instance < backup &&
		  m_instances[ap->m_connectedPort->m_instance].m_nCandidates > 1) {
		backup = ap->m_connectedPort->m_instance;
	      }
	      
	      skip = true;
	      break;
	    }
	  }
	  if (skip) {
	    ocpiDebug("For instance \"%s\" for spec \"%s\" rejecting implementation \"%s%s%s\" with score %u "
		      "from artifact \"%s\" due to connectivity conflict",
		      m_assembly.m_instances[n].m_name.c_str(),
		      m_assembly.m_instances[n].m_specName.c_str(),
		      c.impl->m_metadataImpl.name().c_str(),
		      c.impl->m_instance ? "/" : "",
		      c.impl->m_instance ? ezxml_cattr(c.impl->m_instance, "name") : "",
		      c.score, c.impl->m_artifact.name().c_str());
	    continue;
	  }
	  // If the candidate has feasible containers, evaluate based on score,
	  if (m_curMap && c.score > bestScore) {
	    bestScore = c.score;
	    i->m_impl = c.impl;
	    i->m_chosenCandidate = m;
	    bestMap = m_curMap;
	  }
	  sum |= m_curMap;
	}
	if (!sum)
	  if (backup < nInstances) {
	    ocpiDebug("Backing up from instance %u to instance %u", n, backup);
	    i = &m_instances[backup];
	    i->m_rejectedCandidates |= 1 << i->m_chosenCandidate;
	    i->m_impl = NULL;
	    i->m_nCandidates--;
	    i--;
	    n = backup - 1;
	    continue;
	  } else {
	    std::string err;
	    if (nonReusable)
	      err = "There are not enough containers to run the %d non-reusable implementation";
	    else if (cs.size() > 1)
	      err = "There are no containers for any of the %d suitable implementations";
	    else
	      err = "There are no containers for the %d suitable implementation";
	    err += " for instance %s of component (spec) %s";
	    throw OU::Error(err.c_str(), 
			    cs.size(), m_assembly.m_instances[n].m_name.c_str(),
			    m_assembly.m_instances[n].m_specName.c_str());
	  }
	// The chosen, best, feasible implementation for the instance
	const OL::Implementation &impl = *i->m_impl;

	// Check any assembly-supplied initial properties of the
	// instance against the implementation metadata to see if the
	// names and values are valid. We don't save the results, but
	// later we can assume they are valid.
	const OU::Assembly::Properties &aProps = m_assembly.m_instances[n].m_properties;
	unsigned nPropValues = aProps.size();
	if (nPropValues) {
	  OU::Value *pv = i->m_propValues = new OU::Value[nPropValues];
	  unsigned *pn = i->m_propOrdinals = new unsigned[nPropValues];
	  for (unsigned p = 0; p < nPropValues; p++, pv++, pn++) {
	    // findProperty throws on error if bad name
	    OU::Property &uProp = impl.m_metadataImpl.findProperty(aProps[p].m_name.c_str());
	    const char *err;
	    *pn = uProp.m_ordinal; // remember position in property list 
	    pv->setType(uProp);    // set the data type of the Value from the metadata property
	    if ((err = pv->parse(aProps[p].m_value.c_str())))
	      // Someday a std::string-friendly sprintf
	      throw OU::Error("Value \"%s\" for property \"%s\" of instance \"%s\" of "
			      "worker \"%s\" is invalid for its type",
			      aProps[p].m_value.c_str(), aProps[p].m_name.c_str(),
			      m_assembly.m_instances[n].m_name.c_str(),
			      impl.m_metadataImpl.specName().c_str());
	  }
	}


	// Now call invoke the policy method to map the instances to a container
	policyMap(i, bestMap, sum);
	ocpiInfo("Instance \"%s\" for spec \"%s\" uses implementation \"%s%s%s\" with score %u "
		  "from artifact \"%s\" on container \"%s\"",
		 m_assembly.m_instances[n].m_name.c_str(),
		 m_assembly.m_instances[n].m_specName.c_str(),
		 i->m_impl->m_metadataImpl.name().c_str(),
		 i->m_impl->m_instance ? "/" : "",
		 i->m_impl->m_instance ? ezxml_cattr(i->m_impl->m_instance, "name") : "",
		 bestScore, i->m_impl->m_artifact.name().c_str(),
		 OC::Container::nthContainer(m_usedContainers[i->m_container]).name().c_str());
		  

      }

      
      // Now that we have specific implementations we can do property-aggregation work,
      // since instances can have implementation-specific properties.
      // First, we build the property map that exposes all instance properties as app properties.
      // FIXME: allow XML expression of specific renamed mappings:
      //       <property name="foo" instance="bar" [property="baz"]/>
      i = m_instances;
      // For all instances in the assembly
      m_nProperties = 0;
      for (unsigned n = 0; n < nInstances; n++, i++)
	m_nProperties += i->m_impl->m_metadataImpl.m_nProperties;
      Property *p = m_properties = new Property[m_nProperties];
      i = m_instances;
      for (unsigned n = 0; n < nInstances; n++, i++) {
	unsigned nProps;
	OU::Property *mp = i->m_impl->m_metadataImpl.properties(nProps);
	for (unsigned nn = 0; nn < nProps; nn++, mp++, p++) {
	  p->m_name = m_assembly.m_instances[n].m_name + ":" + mp->m_name;
	  p->m_instance = n;
	  p->m_property = nn;
	  ocpiDebug("Instance %s (%u) property %s (%u) named %s", 
		    m_assembly.m_instances[n].m_name.c_str(), n,
		    mp->m_name.c_str(), nn, p->m_name.c_str());		    
	}
      }
      // To prepare for remote containers, we need to organize the containers we are
      // using by their server.  Then we essentially synthesize an "app" for each server.
      // so the interface to the server is a subset of the info here.
      // There is the top side and the bottom side.
      // THe bottom side is recogniing that you have "remote" connections.
      // The top side is decomposing and merging etc.
      // Assuming that we send the server an XML assembly, it means we need to express remote
      // connections in that xml.


    }
    bool ApplicationI::foundContainer(OCPI::Container::Container &c) {
      m_curMap |= 1 << c.ordinal();
      m_curContainers++;
      return false;
    }

    void ApplicationI::initialize() {


      unsigned nInstances = m_assembly.m_instances.size();
      ocpiDebug("Mapped %d instances to %d containers", nInstances, m_nContainers);

      m_containers = new OC::Container *[m_nContainers];
      m_containerApps = new OC::Application *[m_nContainers];
      m_workers = new OC::Worker *[nInstances];
      for (unsigned n = 0; n < m_nContainers; n++) {
	OC::Container &c = OC::Container::nthContainer(m_usedContainers[n]);
	ocpiDebug("Container %u is %s", n, c.name().c_str());
	m_containers[n] = &c;
	// FIXME: get rid of this cast...
	m_containerApps[n] = static_cast<OC::Application*>(c.createApplication());
      }
      Instance *i = m_instances;
      for (unsigned n = 0; n < nInstances; n++, i++) {
	const OL::Implementation &impl = *i->m_impl;
	OC::Worker &w =
	  m_containerApps[i->m_container]->
	  createWorker(impl.m_artifact,                          // The artifact of the library impl
		       m_assembly.m_instances[n].m_name.c_str(), // The instance name in the assembly
		       impl.m_metadataImpl.m_xml,                // the xml of the impl (from artifact)
		       impl.m_instance,                          // the xml of the fixed instance (from artifact)
		       NULL);                                    // wparams
	m_workers[n] = &w;
	// Now we need to set the initial properties - either from assembly or from defaults
	const OU::Assembly::Properties &aProps = m_assembly.m_instances[n].m_properties;
	unsigned nPropValues = aProps.size();
	for (unsigned p = 0; p < nPropValues; p++)
	  w.setProperty(i->m_propOrdinals[p], i->m_propValues[p]);
	unsigned nProps = impl.m_metadataImpl.m_nProperties;
	OU::Property *prop = impl.m_metadataImpl.m_properties;
	for (unsigned p = 0; p < nProps; p++, prop++)
	  if (prop->m_defaultValue) {
	    bool found = false;
	    for (unsigned m = 0; m < nPropValues; m++)
	      if (i->m_propOrdinals[m] == prop->m_ordinal) {
		found = true;
		break;
	      }
	    if (!found)
	      w.setProperty(prop->m_ordinal, *prop->m_defaultValue);
	  }
      }
      if (m_assembly.m_doneInstance != -1)
	m_doneWorker = m_workers[m_assembly.m_doneInstance];
      unsigned nConns = m_assembly.m_connections.size();
      for (unsigned n = 0; n < nConns; n++) {
	const OU::Assembly::Connection &c = m_assembly.m_connections[n];
	OA::Port &apiPort = m_workers[c.m_ports[0].m_instance]->getPort(c.m_ports[0].m_name.c_str());
	const OU::Assembly::Port &assPort = c.m_ports[0];
	if (c.m_externals.size() == 0)
	  apiPort.connect(m_workers[c.m_ports[1].m_instance]->getPort(c.m_ports[1].m_name.c_str()),
			  assPort.m_parameters, c.m_ports[1].m_parameters);
	else {
	  const OU::Assembly::External &e = c.m_externals[0];
	  if (e.m_url.size())
	    apiPort.connectURL(e.m_url.c_str(), assPort.m_parameters, e.m_parameters);
	  else {
	    //ExternalPort &ep = apiPort.connectExternal(e.m_name.c_str(), assPort.m_parameters, e.m_parameters);
	    
	    m_externals.insert(ExternalPair(e.m_name.c_str(), External(apiPort, e.m_parameters)));
	  }
	}
      }
    }
    void ApplicationI::start() {

      ocpiDebug("Using %d containers to support the application", m_nContainers );

      for (unsigned n = 0; n < m_nContainers; n++)
	m_containerApps[n]->start();
    };
    void ApplicationI::stop() {
      for (unsigned n = 0; n < m_nContainers; n++)
	m_containerApps[n]->stop();
    }
    bool ApplicationI::wait(OS::Timer *timer) {
      if (m_doneWorker)
	return m_doneWorker->wait(timer);
      do {
	bool done = true;
	for (unsigned n = 0; n < m_nContainers; n++)
	  if (!m_containerApps[n]->isDone())
	    done = false;
	if (done)
	  return false;
	OS::sleep(10);
      } while (!timer || !timer->expired());
      return true;
    }

    ExternalPort &ApplicationI::getPort(const char *name) {
      Externals::iterator ei = m_externals.find(name);
      if (ei == m_externals.end())
	throw OU::Error("Unknown external port name for application: \"%s\"", name);
      External &ext = ei->second;
      if (!ext.m_external)
	ext.m_external = &ext.m_port.connectExternal(name, ext.m_params);
      return *ext.m_external;
    }

    Worker &ApplicationI::getPropertyWorker(const char *name) {
      Property *p = m_properties;
      for (unsigned n = 0; n < m_nProperties; n++, p++)
	if (!strcasecmp(name, p->m_name.c_str()))
	  return *m_workers[p->m_instance];
      throw OU::Error("Unknown application property: %s", name);
    }

    static inline const char *maybeColon(const char *name) {
      const char *cp = strchr(name, ':');
      return cp ? cp + 1 : name;
    }
    // FIXME:  consolidate the constructors (others are in OcpiProperty.cxx) (have in internal class for init)
    // FIXME:  avoid the double lookup since the first one gets us the ordinal
    Property::Property(Application &app, const char *aname)
      : m_worker(app.getPropertyWorker(aname)),
	m_readSync(false), m_writeSync(false), m_writeVaddr(0), m_readVaddr(0),
	m_info(m_worker.setupProperty(maybeColon(aname), m_writeVaddr, m_readVaddr))
    {
      m_readSync = m_info.m_readSync;
      m_writeSync = m_info.m_writeSync;
    }

    bool ApplicationI::getProperty(unsigned ordinal, std::string &name, std::string &value) {
      if (ordinal >= m_nProperties)
	return false;
      Property &p = m_properties[ordinal];
      name = p.m_name;
      std::string dummy;
      return m_workers[p.m_instance]->getProperty(p.m_property, dummy, value);
    }

    ApplicationI::Property &ApplicationI::
    findProperty(const char * worker_inst_name, const char * prop_name) {
      std::string nm(worker_inst_name);
      nm += ":";
      nm += prop_name;
      Property *p = m_properties;
      for (unsigned n = 0; n < m_nProperties; n++, p++)
	if (!strcasecmp(nm.c_str(), p->m_name.c_str()))
	  return *p;
      throw OU::Error("Unknown application property: %s", nm.c_str());
    }

    void ApplicationI::
    getProperty(const char * worker_inst_name, const char * prop_name, std::string &value) {
      Property &p = findProperty(worker_inst_name, prop_name);
      std::string dummy;
      m_workers[p.m_instance]->getProperty(p.m_property, dummy, value);	 
    }

    void ApplicationI::
    setProperty(const char * worker_inst_name, const char * prop_name, const char *value) {
      Property &p = findProperty(worker_inst_name, prop_name);
      m_workers[p.m_instance]->setProperty(prop_name, value);
    }

    ApplicationI::Instance::Instance() :
      m_impl(NULL), m_propValues(NULL), m_propOrdinals(NULL), m_rejectedCandidates(0),
      m_nCandidates(0), m_chosenCandidate(0) {
    }
    ApplicationI::Instance::~Instance() {
      delete [] m_propValues;
      delete [] m_propOrdinals;
    }

  }
  namespace API {
    OCPI_EMIT_REGISTER_FULL_VAR( "Get Property", OCPI::Time::Emit::u, 1, OCPI::Time::Emit::State, pegp ); 
    OCPI_EMIT_REGISTER_FULL_VAR( "Set Property", OCPI::Time::Emit::u, 1, OCPI::Time::Emit::State, pesp ); 

    Application::Application(const char *file, const PValue * policy)
      : m_application(*new ApplicationI(file,policy)) {
    }
    Application::Application(const std::string &string, const PValue * policy)
      : m_application(*new ApplicationI(string,policy)) {
    }
    Application::Application(Application & app,  const PValue * policy)
      : m_application(*new ApplicationI(app.m_application.assembly(),policy)) {
    }
    Application::~Application() { delete &m_application; }
    void Application::initialize() { m_application.initialize(); }
    void Application::start() { m_application.start(); }
    void Application::stop() { m_application.start(); }
    bool Application::wait( unsigned timeout_us ) {
      OS::Timer *timer = NULL;
      if (timeout_us) 
	timer = new OS::Timer(timeout_us/1000000ul, (timeout_us%1000000) * 1000ull);
      bool r = m_application.wait(timer);
      delete timer;
      return r;
    }
    ExternalPort &Application::getPort(const char *name) { return m_application.getPort(name); }
    bool Application::getProperty(unsigned ordinal, std::string &name, std::string &value) {
      return m_application.getProperty(ordinal, name, value);
    }
    void Application::getProperty(const char* w, const char* p, std::string &value) {
      OCPI_EMIT_STATE_NR( pegp, 1 );
      m_application.getProperty(w, p, value);
      OCPI_EMIT_STATE_NR( pegp, 0 );

    }
    void Application::setProperty(const char* w, const char* p, const char *value) {
      OCPI_EMIT_STATE_NR( pesp, 1 );
      m_application.setProperty(w, p, value);
      OCPI_EMIT_STATE_NR( pesp, 0 );

    }
    Worker &Application::getPropertyWorker(const char *name) { return m_application.getPropertyWorker(name); }

  }
}
