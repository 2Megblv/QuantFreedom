//+------------------------------------------------------------------+
//| CMemoryMonitor.mqh
//| Array memory usage tracking and high-water mark monitoring
//| Part of Phase 2 Fix 4: Stability through memory awareness
//+------------------------------------------------------------------+

#ifndef __CMEMORYYMONITOR_MQH__
#define __CMEMORYYMONITOR_MQH__

//+------------------------------------------------------------------+
//| CMemoryMonitor Class
//| Purpose: Track dynamic array allocations and alert on capacity
//| Prevents memory exhaustion crashes from unbounded arrays
//+------------------------------------------------------------------+

#define MAX_ARRAY_SIZE 100000

class CMemoryMonitor
{
private:
   int m_allocatedCount;                       // Current allocation count
   int m_highWaterMark;                        // Peak allocation ever reached
   bool m_alertTriggered;                      // Alert flag for >80% capacity
   double m_capacityThreshold;                 // Alert trigger (0.80 = 80%)

public:
   // Constructor
   CMemoryMonitor()
   {
      m_allocatedCount = 0;
      m_highWaterMark = 0;
      m_alertTriggered = false;
      m_capacityThreshold = 0.80;  // Default 80% threshold
   }

   // Destructor
   ~CMemoryMonitor() {}

   //+------------------------------------------------------------------+
   //| TrackAllocation: Update memory usage when array grows
   //+------------------------------------------------------------------+
   
   void TrackAllocation(int newCount)
   {
      if(newCount < 0) newCount = 0;
      if(newCount > MAX_ARRAY_SIZE) newCount = MAX_ARRAY_SIZE;
      
      m_allocatedCount = newCount;
      
      // Update high-water mark
      if(newCount > m_highWaterMark)
      {
         m_highWaterMark = newCount;
      }
      
      // Check threshold
      CheckCapacity();
   }

   //+------------------------------------------------------------------+
   //| GetAllocatedCount: Current allocation size
   //+------------------------------------------------------------------+
   
   int GetAllocatedCount()
   {
      return m_allocatedCount;
   }

   //+------------------------------------------------------------------+
   //| GetHighWaterMark: Peak allocation ever reached
   //+------------------------------------------------------------------+
   
   int GetHighWaterMark()
   {
      return m_highWaterMark;
   }

   //+------------------------------------------------------------------+
   //| GetUsagePercent: Current usage as percentage of max
   //+------------------------------------------------------------------+
   
   double GetUsagePercent()
   {
      if(MAX_ARRAY_SIZE <= 0) return 0.0;
      return ((double)m_allocatedCount / (double)MAX_ARRAY_SIZE) * 100.0;
   }

   //+------------------------------------------------------------------+
   //| IsNearCapacity: Check if usage exceeds threshold
   //+------------------------------------------------------------------+
   
   bool IsNearCapacity(double threshold = 0.80)
   {
      if(MAX_ARRAY_SIZE <= 0) return false;
      double usageRatio = (double)m_allocatedCount / (double)MAX_ARRAY_SIZE;
      return (usageRatio >= threshold);
   }

   //+------------------------------------------------------------------+
   //| CheckCapacity: Internal check and alert trigger
   //+------------------------------------------------------------------+
   
   void CheckCapacity()
   {
      bool nearCapacity = IsNearCapacity(m_capacityThreshold);
      
      // Trigger alert only once per threshold crossing (avoid spam)
      if(nearCapacity && !m_alertTriggered)
      {
         m_alertTriggered = true;
         Print(StringFormat("⚠️  MEMORY ALERT: Array approaching capacity %.1f%% (%d/%d)",
            GetUsagePercent(), m_allocatedCount, MAX_ARRAY_SIZE));
      }
      else if(!nearCapacity && m_alertTriggered)
      {
         m_alertTriggered = false;
         Print(StringFormat("✓ Memory cleared: Back to normal usage (%.1f%%)", GetUsagePercent()));
      }
   }

   //+------------------------------------------------------------------+
   //| SetCapacityThreshold: Adjust alert trigger point
   //+------------------------------------------------------------------+
   
   void SetCapacityThreshold(double threshold)
   {
      if(threshold < 0.0) threshold = 0.0;
      if(threshold > 1.0) threshold = 1.0;
      m_capacityThreshold = threshold;
   }

   //+------------------------------------------------------------------+
   //| LogStatus: Print full memory status to journal
   //+------------------------------------------------------------------+
   
   void LogStatus()
   {
      Print("");
      Print("════════════════════════════════════════════════════");
      Print("MEMORY MONITOR STATUS");
      Print("════════════════════════════════════════════════════");
      Print(StringFormat("Current Allocation: %d (%.1f%%)", m_allocatedCount, GetUsagePercent()));
      Print(StringFormat("High Water Mark: %d (%.1f%%)", m_highWaterMark, 
         ((double)m_highWaterMark / (double)MAX_ARRAY_SIZE) * 100.0));
      Print(StringFormat("Max Capacity: %d", MAX_ARRAY_SIZE));
      Print(StringFormat("Alert Threshold: %.0f%%", m_capacityThreshold * 100.0));
      Print(StringFormat("Alert Status: %s", m_alertTriggered ? "🔴 TRIGGERED" : "✓ OK"));
      Print("════════════════════════════════════════════════════");
      Print("");
   }

   //+------------------------------------------------------------------+
   //| Reset: Clear high-water mark and alert flag
   //+------------------------------------------------------------------+
   
   void Reset()
   {
      m_highWaterMark = m_allocatedCount;
      m_alertTriggered = false;
      Print("✓ Memory monitor reset");
   }

   //+------------------------------------------------------------------+
   //| GetCapacityStatus: Human-readable status string
   //+------------------------------------------------------------------+
   
   string GetCapacityStatus()
   {
      if(IsNearCapacity())
         return StringFormat("⚠️  NEAR CAPACITY (%.1f%%)", GetUsagePercent());
      else if(GetUsagePercent() > 50.0)
         return StringFormat("⚡ MODERATE (%.1f%%)", GetUsagePercent());
      else
         return StringFormat("✓ OK (%.1f%%)", GetUsagePercent());
   }
};

#endif
