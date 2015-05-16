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

#include <cstring>
#include <cstdio>
#include <cassert>
#include <climits>
#include "OcpiOsAssert.h"
#include "OcpiUtilEzxml.h"
#include "OcpiUtilMisc.h"
#include "OcpiUtilProperty.h"
#include "OcpiUtilValue.h"

// Used both in spec and in impl
#define ACCESS_ATTRIBUTES \
  "Readable", "Writable", "Volatile", "Initial", "Padding", "Parameter"

#define PROPERTY_ATTRIBUTES \
  OCPI_UTIL_MEMBER_ATTRS, ACCESS_ATTRIBUTES, "IsTest", "Default"

// Readable/writable/volatile/initial are here redundantly to allow the implementation to
// have more access than the spec.  I.e. the spec might not specify readable,
// but for debugging the implementation might want it.  Similarly, the spec
// might say "initial", but the implementation supports dynamic writability

#define IMPL_ATTRIBUTES \
  ACCESS_ATTRIBUTES, \
  "ReadSync",   /* impl says you need before query */\
  "WriteSync",  /* impl says you need afterconfig */\
  "ReadBarrier",   /* impl says you need before query */\
  "WriteBarrier",  /* impl says you need afterconfig */\
  "ReadError",  /* impl says reading this can return an error */\
  "WriteError", /* impl says writing this can return an error */\
  "Indirect",   /* impl is supplying an indirect address */	\
    "Debug",       /* property is for debug only */		\
  "ReadScalable"       /* property is for debug only */     \


namespace OCPI {
  namespace API {
    PropertyInfo::PropertyInfo()
      : m_readSync(false), m_writeSync(false), m_isWritable(false),
	m_isReadable(false), m_readError(false), m_writeError(false),
	m_isVolatile(false), m_isInitial(false), m_isIndirect(false),
	m_indirectAddr(0)
    {}
  }
  namespace Util {
    namespace OE = EzXml;
    namespace OA = OCPI::API;
    Property::Property()
      : m_smallest(0), m_granularity(0), m_isParameter(false), m_isSub32(false),
	m_isTest(false), m_dataOffset(0), m_paramOrdinal(0),
	m_readBarrier(false), m_writeBarrier(false), m_reduction(None) {
    }
    Property::~Property() {
    }
    // parse a value for this property, which may be a struct
    // instance property values in an assembly.
    const char *
    Property::parseValue(const char *unparsed, Value &value, const char *end) const {
      if (!value.m_vt)
	value.setType(*this);
      return value.parse(unparsed, end);
    }

    // FIXME find the caller and nuke this one
    const char *
    Property::parse(ezxml_t prop, unsigned ordinal) {
      return parse(prop, true, ordinal);
    }

    const char *
    Property::parseAccess(ezxml_t prop, bool addAccess) {
      const char *err;
      if ((err = OE::getBoolean(prop, "Readable", &m_isReadable, addAccess)) ||
	  (err = OE::getBoolean(prop, "Writable", &m_isWritable, addAccess)) ||
	  (err = OE::getBoolean(prop, "Initial", &m_isInitial, addAccess)) ||
	  (err = OE::getBoolean(prop, "Volatile", &m_isVolatile, addAccess)) ||
	  (err = OE::getBoolean(prop, "Parameter", &m_isParameter, addAccess)) ||
	  (err = OE::getBoolean(prop, "Padding", &m_isPadding, false)))
	return err;
      if (m_isInitial)
	m_isWritable = true;
      if (m_isVolatile)
	m_isReadable = true;
      return NULL;
    }
    // Common checking for initial parsing and add-impl-stuff parsing
    const char *
    Property::parseCheck() {
      if (m_isParameter && ((m_isWritable && !m_isInitial) || m_isIndirect))
	return esprintf("Property \"%s\" is a parameter and can't be writable or indirect",
			m_name.c_str());
      if (!m_isWritable && !m_isReadable && !m_isParameter && !m_isPadding)
	return esprintf("Property \"%s\" is not readable or writable or padding or a parameter",
			m_name.c_str());
      return NULL;
    }
    // This is parsing a newly create property that might be only defined in
    // an implementation (includeImpl == true)
    const char *
    Property::parse(ezxml_t prop, bool includeImpl, unsigned ordinal,
		    const IdentResolver *resolv) {
      const char *err;

      if ((err = includeImpl ?
	   OE::checkAttrs(prop, "Name", PROPERTY_ATTRIBUTES, IMPL_ATTRIBUTES, NULL) :
	   OE::checkAttrs(prop, "Name", PROPERTY_ATTRIBUTES, NULL)) ||
	  includeImpl && (err = parseImplAlso(prop)) ||
	  (err = parseAccess(prop, false)) ||
	  (err = Member::parse(prop, !m_isParameter, true, "default", ordinal, resolv)))
	return err;
      // This call is solely used for sub32 determination.  The rest are ignored here.
      // FIXME: move this determination into the parse to avoid all this...
      size_t maxAlign = 1; // dummy and not really used since property sheet is zero based anyway
      size_t minSize = 0;
      bool diverseSizes = false;
      bool unBoundedDummy;   // we are precluding unbounded in any case
      size_t myOffset = 0;
      if ((err = Member::offset(maxAlign, myOffset, minSize, diverseSizes, m_isSub32,
				unBoundedDummy)))
	return err;
#if 0 // moved to parse.cxx of ocpigen
      if (m_isSub32)
	sub32Configs = true;
#endif
      return parseCheck();
    }
    // A higher up is creating offsets in a list of properties after we know it all
    // Here is where is need to ensure that all aspects of the underlying data type
    // are fully resolved.
    const char *Property::
    offset(size_t &cumOffset, uint64_t &sizeofConfigSpace, const IdentResolver *resolver) {
      const char *err = NULL;
      if (resolver && (err = finalize(*resolver, !m_isParameter)))
	return err;
      if (m_isIndirect) {
	uint64_t top = m_indirectAddr;
	top += m_nBytes;
	if (top > sizeofConfigSpace)
	  sizeofConfigSpace = top;
	m_offset = m_indirectAddr;
      } else if (!m_isParameter) {
	cumOffset = roundUp(cumOffset, m_align);
	m_offset = cumOffset;
	cumOffset += m_nBytes;
	if (cumOffset > sizeofConfigSpace)
	  sizeofConfigSpace = cumOffset;
      }
      return err;
    }

#if 0
    const char *Property::
    checkType(Scalar::Type ctype, unsigned n, bool write) {
      if (write && !isWritable)
	return "trying to write a non-writable property";
      if (!write && !isReadable)
	return "trying to read a non-readable property";
      if (isStruct)
	return "struct type used as scalar type";
      if (ctype != members->type.scalar)
	return "incorrect type for this property";
      if (write && n > members->type.length)
	return "sequence or array too long for this property";
      if (!write && n < members->type.length)
	return "sequence or array not large enough for this property";
      return 0;
    }
#endif

    // Shared routine to parse impl-only attributes. Parse access before this.
    const char *Property::
    parseImplAlso(ezxml_t prop) {
      const char *err;
      if ((err = OE::getBoolean(prop, "ReadSync", &m_readSync)) ||
	  (err = OE::getBoolean(prop, "WriteSync", &m_writeSync)) ||
	  (err = OE::getBoolean(prop, "ReadBarrier", &m_readBarrier)) ||
	  (err = OE::getBoolean(prop, "WriteBarrier", &m_writeBarrier)) ||
	  (err = OE::getBoolean(prop, "ReadError", &m_readError)) ||
	  (err = OE::getBoolean(prop, "WriteError", &m_writeError)) ||
	  (err = OE::getBoolean(prop, "IsTest", &m_isTest)) ||
	  (err = OE::getBoolean(prop, "Debug", &m_isDebug)) ||
	  // FIXME: consider allowing this only for HDL somehow.
	  (err = OE::getNumber(prop, "Indirect", &m_indirectAddr, &m_isIndirect, 0, true)))
	return err;
      static const char *reduceNames[] = {
#define OCPI_REDUCE(c) #c,	  
	OCPI_REDUCTIONS
#undef OCPI_REDUCE
	NULL
      };
      size_t n;
      if ((err = OE::getEnum(prop, "readScalable", reduceNames, "reduction operation", n,
			     m_reduction)))
	return err;
      m_reduction = (Reduction)n;
      // FIXME: add overrides: writable clears initial
      return 0;
    }

    // This parses something that is adding impl attributes to an existing property
    const char *Property::
    parseImpl(ezxml_t x) {
      const char *err;
      if ((err = OE::checkAttrs(x, "Name", IMPL_ATTRIBUTES, "default", NULL)) ||
	  (err = parseAccess(x, true)) ||
	  // FIXME: should this be illegal if the property is not initiall or writable?
	  (err = parseDefault(x, "default")) ||
	  (err = parseImplAlso(x)))
	return err;
      return parseCheck();
    }
    const char *Property::getValue(ExprValue &val) {
      if (!m_default)
	return esprintf("property \"%s\" has no value", m_name.c_str());
      if (m_arrayRank || m_isSequence || m_baseType == OA::OCPI_Struct ||
	  m_baseType == OA::OCPI_Type)
	return esprintf("property \"%s\" is an array/sequence/struct", m_name.c_str());
      return m_default->getValue(val);
    }
  }
}

