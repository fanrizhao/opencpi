/*
<<<<<<< HEAD
 * THIS FILE WAS ORIGINALLY GENERATED ON Tue Sep  8 16:59:19 2015 EDT
=======
 * THIS FILE WAS ORIGINALLY GENERATED ON Thu Sep 10 10:28:53 2015 EDT
>>>>>>> 0355dbaccdd79aa08d0bd2d0594c84e9fc732b18
 * BASED ON THE FILE: ptest_cc.xml
 * YOU *ARE* EXPECTED TO EDIT IT
 *
 * This file contains the implementation skeleton for the ptest_cc worker in C++
 */

#include "ptest_cc-worker.hh"

using namespace OCPI::RCC; // for easy access to RCC data types and constants
using namespace Ptest_ccWorkerTypes;

class Ptest_ccWorker : public Ptest_ccWorkerBase {
  RCCResult run(bool /*timedout*/) {
    return RCC_DONE;
  }
};

PTEST_CC_START_INFO
// Insert any static info assignments here (memSize, memSizes, portInfo)
// e.g.: info.memSize = sizeof(MyMemoryStruct);
PTEST_CC_END_INFO
