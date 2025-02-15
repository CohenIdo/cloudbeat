// Licensed to Elasticsearch B.V. under one or more contributor
// license agreements. See the NOTICE file distributed with
// this work for additional information regarding copyright
// ownership. Elasticsearch B.V. licenses this file to you under
// the Apache License, Version 2.0 (the "License"); you may
// not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

package transformer

import (
	"github.com/elastic/cloudbeat/config"
	"github.com/elastic/cloudbeat/resources/fetching"
	"github.com/elastic/cloudbeat/version"
	"github.com/elastic/elastic-agent-libs/logp"
	"k8s.io/client-go/kubernetes"
)

type ResourceTypeMetadata struct {
	fetching.CycleMetadata
	Type string
}

type CommonDataProvider struct {
	log        *logp.Logger
	kubeClient kubernetes.Interface
	cfg        config.Config
}

type CommonData struct {
	clusterId   string
	nodeId      string
	versionInfo version.CloudbeatVersionInfo
}

type CommonDataInterface interface {
	GetData() CommonData
	GetResourceId(fetching.ResourceMetadata) string
	GetVersionInfo() version.CloudbeatVersionInfo
}
