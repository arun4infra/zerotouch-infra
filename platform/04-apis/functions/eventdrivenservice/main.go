package main

import (
	"context"
	"fmt"

	"github.com/crossplane/crossplane-runtime/pkg/errors"
	"github.com/crossplane/crossplane-runtime/pkg/logging"
	fnv1beta1 "github.com/crossplane/function-sdk-go/proto/v1beta1"
	"github.com/crossplane/function-sdk-go/request"
	"github.com/crossplane/function-sdk-go/response"
	corev1 "k8s.io/api/core/v1"
)

// Function implements the EventDrivenService composition function
type Function struct {
	fnv1beta1.UnimplementedFunctionRunnerServiceServer
	log logging.Logger
}

// SecretRef represents a secret reference from the claim
type SecretRef struct {
	Name    string      `json:"name"`
	Env     []EnvKeyMap `json:"env,omitempty"`
	EnvFrom bool        `json:"envFrom,omitempty"`
}

// EnvKeyMap represents a secret key to environment variable mapping
type EnvKeyMap struct {
	SecretKey string `json:"secretKey"`
	EnvName   string `json:"envName"`
}

// InitContainer represents init container configuration
type InitContainer struct {
	Command []string `json:"command"`
	Args    []string `json:"args,omitempty"`
}

// RunFunction processes the EventDrivenService claim and builds env/envFrom arrays
func (f *Function) RunFunction(ctx context.Context, req *fnv1beta1.RunFunctionRequest) (*fnv1beta1.RunFunctionResponse, error) {
	f.log.Info("Processing EventDrivenService composition function")

	rsp := response.To(req, response.DefaultTTL)

	// Get the observed composite resource
	oxr, err := request.GetObservedCompositeResource(req)
	if err != nil {
		response.Fatal(rsp, errors.Wrap(err, "cannot get observed composite resource"))
		return rsp, nil
	}

	// Extract spec fields
	spec := oxr.Resource.Object["spec"].(map[string]interface{})
	
	// Get NATS configuration for base env vars
	natsConfig := spec["nats"].(map[string]interface{})
	natsURL := natsConfig["url"].(string)
	natsStream := natsConfig["stream"].(string)
	natsConsumer := natsConfig["consumer"].(string)

	// Build base environment variables (NATS)
	envVars := []corev1.EnvVar{
		{Name: "NATS_URL", Value: natsURL},
		{Name: "NATS_STREAM_NAME", Value: natsStream},
		{Name: "NATS_CONSUMER_GROUP", Value: natsConsumer},
	}

	// Build envFrom array
	var envFromSources []corev1.EnvFromSource

	// Process secretRefs if present
	if secretRefsRaw, ok := spec["secretRefs"]; ok && secretRefsRaw != nil {
		secretRefs := secretRefsRaw.([]interface{})
		
		for _, refRaw := range secretRefs {
			ref := refRaw.(map[string]interface{})
			secretName := ref["name"].(string)

			// Handle individual key mappings (env)
			if envMappings, ok := ref["env"]; ok && envMappings != nil {
				mappings := envMappings.([]interface{})
				for _, mappingRaw := range mappings {
					mapping := mappingRaw.(map[string]interface{})
					secretKey := mapping["secretKey"].(string)
					envName := mapping["envName"].(string)

					envVars = append(envVars, corev1.EnvVar{
						Name: envName,
						ValueFrom: &corev1.EnvVarSource{
							SecretKeyRef: &corev1.SecretKeySelector{
								LocalObjectReference: corev1.LocalObjectReference{
									Name: secretName,
								},
								Key: secretKey,
							},
						},
					})
				}
			}

			// Handle bulk mounting (envFrom)
			if envFrom, ok := ref["envFrom"]; ok && envFrom.(bool) {
				envFromSources = append(envFromSources, corev1.EnvFromSource{
					SecretRef: &corev1.SecretEnvSource{
						LocalObjectReference: corev1.LocalObjectReference{
							Name: secretName,
						},
					},
				})
			}
		}
	}

	// Get the Deployment resource from desired composed resources
	desired, err := request.GetDesiredComposedResources(req)
	if err != nil {
		response.Fatal(rsp, errors.Wrap(err, "cannot get desired composed resources"))
		return rsp, nil
	}

	// Find the Deployment resource
	deploymentResource, ok := desired["deployment"]
	if !ok {
		response.Fatal(rsp, errors.New("deployment resource not found in desired state"))
		return rsp, nil
	}

	// Extract the Deployment manifest
	manifest := deploymentResource.Resource.Object["spec"].(map[string]interface{})["forProvider"].(map[string]interface{})["manifest"].(map[string]interface{})
	podSpec := manifest["spec"].(map[string]interface{})["template"].(map[string]interface{})["spec"].(map[string]interface{})
	containers := podSpec["containers"].([]interface{})
	mainContainer := containers[0].(map[string]interface{})

	// Update main container env and envFrom
	mainContainer["env"] = envVarsToInterface(envVars)
	if len(envFromSources) > 0 {
		mainContainer["envFrom"] = envFromSourcesToInterface(envFromSources)
	}

	// Handle optional init container
	if initContainerRaw, ok := spec["initContainer"]; ok && initContainerRaw != nil {
		initConfig := initContainerRaw.(map[string]interface{})
		
		// Get image from main container
		image := mainContainer["image"].(string)
		
		// Build init container
		initContainer := map[string]interface{}{
			"name":    "run-migrations",
			"image":   image,
			"command": initConfig["command"],
			"env":     envVarsToInterface(envVars),
			"securityContext": map[string]interface{}{
				"runAsNonRoot":             true,
				"runAsUser":                1000,
				"allowPrivilegeEscalation": false,
				"capabilities": map[string]interface{}{
					"drop": []string{"ALL"},
				},
				"seccompProfile": map[string]interface{}{
					"type": "RuntimeDefault",
				},
			},
		}

		// Add args if present
		if args, ok := initConfig["args"]; ok && args != nil {
			initContainer["args"] = args
		}

		// Add envFrom if present
		if len(envFromSources) > 0 {
			initContainer["envFrom"] = envFromSourcesToInterface(envFromSources)
		}

		// Set init containers array
		podSpec["initContainers"] = []interface{}{initContainer}
	}

	// Update the desired resource
	desired["deployment"] = deploymentResource

	f.log.Info("Successfully processed EventDrivenService composition function")
	return rsp, nil
}

// Helper functions to convert Go types to interface{} for JSON serialization
func envVarsToInterface(envVars []corev1.EnvVar) []interface{} {
	result := make([]interface{}, len(envVars))
	for i, ev := range envVars {
		envMap := map[string]interface{}{
			"name": ev.Name,
		}
		if ev.Value != "" {
			envMap["value"] = ev.Value
		}
		if ev.ValueFrom != nil {
			valueFrom := map[string]interface{}{}
			if ev.ValueFrom.SecretKeyRef != nil {
				valueFrom["secretKeyRef"] = map[string]interface{}{
					"name": ev.ValueFrom.SecretKeyRef.Name,
					"key":  ev.ValueFrom.SecretKeyRef.Key,
				}
			}
			envMap["valueFrom"] = valueFrom
		}
		result[i] = envMap
	}
	return result
}

func envFromSourcesToInterface(sources []corev1.EnvFromSource) []interface{} {
	result := make([]interface{}, len(sources))
	for i, source := range sources {
		sourceMap := map[string]interface{}{}
		if source.SecretRef != nil {
			sourceMap["secretRef"] = map[string]interface{}{
				"name": source.SecretRef.Name,
			}
		}
		result[i] = sourceMap
	}
	return result
}

func main() {
	// Function entry point would be here
	// This would typically use the Crossplane function SDK to start the gRPC server
	fmt.Println("EventDrivenService Composition Function")
}
