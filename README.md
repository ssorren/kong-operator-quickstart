# Kong Operator Quickstart
 To deploy Kong Gateway and or Kong AI Gateway via Kubernetes, we will need to set up the following entities:

- The [Kong Operator](https://developer.konghq.com/operator/) itself.
- A Kubernetes Secret which contains konnect a access token (either a personal access token or a system access token).
- A KonnectAPIAuthConfiguration resource. This entity instructs the operator to use the defined secret when making calls to the Konnect APIs.
- A KonnectGatewayControlPlane resource. This is the Konnect Control Plane. It can be fully managed by Kubernetes, or it can be a mirror of a pre-existing control plane (created manually in the UI or through terraform, kongctl, API calls etc.). You may also want to use mirrored control planes if you want to run data planes on multiple clusters for the same control plane, in which case you would need to avoid conflicts in control plane ownership.
- A KonnectExtension resource. This will link DataPlane resources to a KonnectGatewayControlPlane. It also controls certificate generation for data plane to control plane mTLS communication.
- A DataPlane resource. This is the reource that actually serves traffic on your cluster. This resource will also manage LoadBalancer instantiation, TLS certs etc.

In the steps below, some of these entities will be combined into files together, but it is important to understand each entitiy and waht it is reponsible for.


### Step 0) Pre-reqs
The examples here use commonly available command line tools such as:
- kubectl
- helm
- envsubst
- jq
- k9s (optional but a very good utility)

Please ensure these are installed via `homebrew` for Mac, or whatever package manager is appropriate for the operating system you will be using. Beyond this, we're assuming you have the following:

- You have cloned this repo to the workstation you will the executing CLI commands from.
- A Kubernetes cluster running.
- Access to the cluster via `kubectl`
- Access to your [Konnect Organization](https://cloud.konghq.com/) (trial or paid)
- Your Kubernetes cluster needs to be able to create load balancers. ***This varies by provider. For example, EKS requires permissions and a load balancer controller to be set up on the cluster. Please refer to your providers documentation.***
  - If you are running on a local cluster and do not have load balancer installed, metal-lb is a good choice. To install on your local cluster, run the following:

```shell
## Only run if you are using a local K8s cluster 
## and you do not already have a load balancer like metal-lb installed
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.15.2/config/manifests/metallb-native.yaml
kubectl get pods -n metallb-system
kubectl apply -f metal-lb.yaml
```


### Step 1) Install Kong Operator

First install the Kong helm charts with the following commands:
```shell
helm repo add kong https://charts.konghq.com
helm repo update kong
```

Next we're goping to install the omg Operator itself.
Please note the `env.VALIDATE_IMAGES=false`. If you are using container images with custom plugins, this will ensure you can use images with versions that don't conform to the Kong versioning scheme. We're also going to create a namespace for our kong resources. In our examples, we are using `kong` to keep things simple.

```shell
helm upgrade --install kong-operator kong/kong-operator -n kong-system \
  --create-namespace \
  --set image.tag=2.0.5 \
  --set env.ENABLE_CONTROLLER_KONNECT=true \
  --set env.VALIDATE_IMAGES=false && \
kubectl create namespace kong
```

### Step 2) Environment Variables
The kubernetes manifests in this repo are designed to be used with environment variables. Since many of the reources reference each other, we are using a `$CONRTOL_PLANE_NAME` variable along with a naming convention to ensure the relationships are respected and there are no collisions when multiple gateways are defined. You may want to use your own naming convention in your dev/production environments, but the naming convention used here is as follows:
| Var                                    | Resource                            |
| :------------------------------------- | :---------------------------------- |
| **${CONTROL_PLANE_NAME}**              | KonnectGatewayControlPlane          |
| **${CONTROL_PLANE_NAME}-extension**    | KonnectExtension                    |
| **${CONTROL_PLANE_NAME}-dataplane**    | DataPlane                           |
| **${CONTROL_PLANE_NAME}-loadbalancer** | LoadBalancer for the DataPlane      |
| **${CONTROL_PLANE_NAME}-secret**       | Secret containing your access token |
| **${CONTROL_PLANE_NAME}-api-auth**     | KonnectAPIAuthConfiguration         |

Technically speaking, the *Secret* and *KonnectAPIAuthConfiguration* resources can be used for several control planes. Depending on your security requirements, you could re-use these resources by giving them a less specific names such as `konnect-token-secret` and `konnect-api-auth`. In this example, we are creating one of each per control plane. This helps limit blast radius if tokens expire or need to be invaliated for other reasons.

Obtain a Konnect [personal access token](https://cloud.konghq.com/global/account/tokens) and store it as an environment variable in your shell session. For producion environments, you will likely want a [system access token](https://cloud.konghq.com/global/organization/system-accounts). For our control plane name, we are using `ko-quickstart`. Feel free to use whatever name you like. The ports listed are below are for the load balancer, use whatever ports are appropriate for your environment.

```shell
export CONTROL_PLANE_NAME=ko-quickstart
export KONG_GATEWAY_IMAGE="kong/kong-gateway:3.12"
export KONNECT_API_ENDPOINT=us.api.konghq.com # if you are not using the US region, replace with the appropriate endpoint
export LB_HTTP_PORT=8080
export LB_HTTPS_PORT=8443
export PAT=<your token>
```

## Deployment
### Step 3) Ensure the kong-operator pod is up and running
```shell
kubectl --namespace kong-system get pods
```
You should see output like this:
```shell
➜  kong-operator-quickstart git:(main) ✗ kubectl --namespace kong-system get pods
NAME                                                             READY   STATUS    RESTARTS   AGE
kong-operator-kong-operator-controller-manager-c5db8cb56-2rwjt   1/1     Running   0          3d8h
```

### Step 4) Deploy the Secret and KonnectAPIAuthConfiguration
```shell
envsubst < konnect-auth.yaml | kubectl apply -f -
```

A `kubectl get KonnectAPIAuthConfiguration ${CONTROL_PLANE_NAME}-api-auth -n kong` should yield something like this:
```shell
NAME                     VALID   ORGID                                  SERVERURL
ko-quickstart-api-auth   True    d67f85bd-6355-4003-8de3-fc2a3c76bead   https://us.api.konghq.com
```

### Step 5a) Deploy the Control Plane
We have two options here. If we're creating a control plane from scratch, we can use the Kong Operator to manage it. If so, run the following command:

```shell
envsubst < control-plane.yaml | kubectl apply -f -
```

You should now see your newly created control plane in the [Konnect UI](https://cloud.konghq.com/us/gateway-manager/):
![Control Plane](/assets/controlplane.png "Control Plane Created")


### Step 5b) Control Plane Mirror Option

If we want to mirror a pre-existing control plane, we will use the contol-plane-morror.yaml file. However, we will need to get the control plane id for this approach to work. You can get this from the Konnect UI, but there is a CLI command which will owrk as well:

```shell
export CONTROL_PLANE_ID=$(curl -s -X GET "https://${KONNECT_API_ENDPOINT}$/v2/control-planes?filter\[name\]=${CONTROL_PLANE_NAME}" -H "Authorization: Bearer ${PAT}" | jq -r '.data[0].id' )
echo $CONTROL_PLANE_ID
```

In your terminal, you should see a UUID string from the above command if successful. We are now ready to run the following: 

```shell
envsubst < control-plane-mirror.yaml | kubectl apply -f -
```




### Step 6) Deploy the Data Plane
Please inspect your local copy of [data-plane.yaml](data-plane.yaml). There are commented sections which you may want to implement. For example, if you are running on EKS, you may want to customize the load balancer annotations. The default for Kong is an external L4 load balancer.

Finally, out DataPlane resource is ready to deploy with the following command:
```shell
envsubst < data-plane.yaml | kubectl apply -f -
```

Your data plane pod should now be strting up. You can check on the status via k9s, or using kubectl directly. If you check your Konnect UI, you should be able to see it in the *Data Plane Nodes* section:

![Data Plane](/assets/dataplane.png "Data Plane Connected")

You can test availability with curl, assuming your testing on localhost:

```
curl http://localhost:$LB_HTTP_PORT/
```

Should yield something like the following:

```json
{
  "message":"no Route matched with those values",
  "request_id":"2e1a1e2e29f94c14a5a4685371512908"
}
```

You are now ready to configure your services, routes and plugins and begin serving traffic. 