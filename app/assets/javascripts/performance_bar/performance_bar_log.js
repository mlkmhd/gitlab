/* eslint-disable no-console */
import { onCLS, onFCP, onINP, onLCP, onTTFB } from 'web-vitals';
import { PERFORMANCE_TYPE_MARK, PERFORMANCE_TYPE_MEASURE } from '~/performance/constants';

const initVitalsLog = () => {
  const reportVital = (data) => {
    console.log(`${String.fromCodePoint(0x1f4c8)} ${data.name} : `, data);
  };

  console.log(
    `${String.fromCodePoint(
      0x1f4d1,
    )} Web vitals are logged each time they change, CLS when you switch away from the tab. The latest line for each metric is its current value`,
  );
  onCLS(reportVital); // Changes on every layout shift, so only log the final value
  onFCP(reportVital, { reportAllChanges: true });
  onINP(reportVital, { reportAllChanges: true });
  onLCP(reportVital, { reportAllChanges: true });
  onTTFB(reportVital, { reportAllChanges: true });
};

const logUserTimingMetrics = () => {
  const metricsProcessor = (list) => {
    const entries = list.getEntries();
    entries.forEach((entry) => {
      const { name, entryType, startTime, duration } = entry;
      const typeMapper = {
        [PERFORMANCE_TYPE_MARK]: String.fromCodePoint(0x1f3af),
        [PERFORMANCE_TYPE_MEASURE]: String.fromCodePoint(0x1f4d0),
      };
      console.group(`${typeMapper[entryType]} ${name}`);
      if (entryType === PERFORMANCE_TYPE_MARK) {
        console.log(`Start time: ${startTime}`);
      } else if (entryType === PERFORMANCE_TYPE_MEASURE) {
        console.log(`Duration: ${duration}`);
      }
      console.log(entry);
      console.groupEnd();
    });
  };
  const observer = new PerformanceObserver(metricsProcessor);
  observer.observe({ entryTypes: [PERFORMANCE_TYPE_MEASURE, PERFORMANCE_TYPE_MARK] });
};

const initPerformanceBarLog = () => {
  console.log(
    `%c ${String.fromCodePoint(0x1f98a)} GitLab performance bar`,
    'width:100%; background-color: #292961; color: #FFFFFF; padding: 10px; display:block;',
  );

  initVitalsLog();
  logUserTimingMetrics();
};

export default initPerformanceBarLog;
