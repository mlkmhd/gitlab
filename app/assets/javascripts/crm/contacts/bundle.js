import Vue from 'vue';
import VueApollo from 'vue-apollo';
import VueRouter from 'vue-router';
import { parseBoolean } from '@gitlab/frontend-utils';
import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import createDefaultClient from '~/lib/graphql';
import CrmContactsApp from './contacts_app.vue';
import routes from './routes';

Vue.use(VueApollo);
Vue.use(VueRouter);

export default () => {
  const el = document.getElementById('js-crm-contacts-app');

  const apolloProvider = new VueApollo({
    defaultClient: createDefaultClient(),
  });

  if (!el) {
    return false;
  }

  const {
    basePath,
    groupFullPath,
    groupWorkItemsPath,
    groupOrganizationsPath,
    canCreateCrmContact,
    canUpdateCrmContact,
    canReadCrmOrganization,
    groupId,
    textQuery,
  } = el.dataset;

  const router = new VueRouter({
    base: basePath,
    mode: 'history',
    routes,
  });

  return initVueApp({
    el,
    name: 'CrmContactsAppRoot',
    router,
    apolloProvider,
    provide: {
      groupFullPath,
      groupWorkItemsPath,
      groupOrganizationsPath,
      canCreateCrmContact: parseBoolean(canCreateCrmContact),
      canUpdateCrmContact: parseBoolean(canUpdateCrmContact),
      canReadCrmOrganization: parseBoolean(canReadCrmOrganization),
      groupId,
      textQuery,
    },
    component: CrmContactsApp,
  });
};
