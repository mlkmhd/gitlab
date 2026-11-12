<script>
const PARAGRAPH = ['gl-w-17/20', 'gl-w-full', 'gl-w-17/20', 'gl-w-full', 'gl-w-11/20'];
const SHORT_PARAGRAPH = ['gl-w-17/20', 'gl-w-full', 'gl-w-11/20'];

export default {
  name: 'WorkplanSkeleton',
  sections: [
    { headingClass: 'gl-h-6 gl-w-12', lines: PARAGRAPH },
    { headingClass: 'gl-mt-3 gl-h-4 gl-w-37', lines: SHORT_PARAGRAPH },
    { headingClass: 'gl-h-6 gl-w-15', lines: PARAGRAPH },
    { headingClass: 'gl-mt-3 gl-h-4 gl-w-30', lines: SHORT_PARAGRAPH },
  ],
};
</script>

<template>
  <div class="gl-flex gl-flex-col gl-gap-7" data-testid="workplan-skeleton">
    <div v-for="(section, sectionIndex) in $options.sections" :key="sectionIndex">
      <div
        class="gl-animate-skeleton-loader gl-max-w-full gl-rounded-md"
        :class="section.headingClass"
      ></div>
      <div class="gl-mt-5 gl-flex gl-flex-col gl-gap-4">
        <div
          v-for="(lineClass, lineIndex) in section.lines"
          :key="lineIndex"
          class="gl-animate-skeleton-loader gl-h-3 gl-max-w-full gl-rounded-sm"
          :class="lineClass"
        ></div>
      </div>
    </div>
  </div>
</template>
