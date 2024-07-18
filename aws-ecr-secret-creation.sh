#!/bin/sh
set -e
## curl -fsSl https://raw.githubusercontent.com/oraculox/sh/main/aws-ecr-secret-creation.sh -o aws-ecr-secret-creation.sh && sh aws-ecr-secret-creation.sh
### Create cronjob.
echo "## Creating k8s Cronjob to run every 6h to renew AWS ECR token to allow pull images from Private ECR. ##"
echo ""
read -p "enter AWS Region (default is: eu-west-2):" BREGION
read -p "enter AWS Account:" BAWS_ACCOUNT
read -p "enter AWS Secret:" BAWS_SECRET
read -p "enter AWS Key:" BAWS_KEY
read -p "enter namaspace:" BNAMESPACE

echo ''
echo 'AWS Region is: '${BREGION}
echo 'AWS Account is: '$BAWS_ACCOUNT
echo 'AWS Secretis : '$BAWS_SECRET
echo 'AWS Key is: '$BAWS_KEY
echo 'namaspace is: '$BNAMESPACE
echo ''

read -p "Do you confirm the details? (y/N)?" CONFIRM
if [ "$CONFIRM" = "y" ]; then
cat >> cronjob.yaml <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  labels:
    app.kubernetes.io/managed-by: Helm
  name: sa-ecr-token-helper
  namespace: BNAMESPACE
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  labels:
    app.kubernetes.io/managed-by: Helm
  name: ecr-token-helper
  namespace: BNAMESPACE
rules:
- apiGroups:
  - ""
  resources:
  - secrets
  - serviceaccounts
  - serviceaccounts/token
  verbs:
  - delete
  - create
  - patch
  - get
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  labels:
    app.kubernetes.io/managed-by: Helm
  name: ecr-token-helper
  namespace: BNAMESPACE
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: ecr-token-helper
subjects:
- kind: ServiceAccount
  name: sa-ecr-token-helper
  namespace: BNAMESPACE
---
apiVersion: batch/v1
kind: CronJob
metadata:
  labels:
    app.kubernetes.io/managed-by: Helm
  name: ecr-cred-helper
  namespace: BNAMESPACE
spec:
  concurrencyPolicy: Allow
  failedJobsHistoryLimit: 1
  jobTemplate:
    metadata:
      creationTimestamp: null
    spec:
      template:
        metadata:
          creationTimestamp: null
        spec:
          containers:
          - command:
            - /bin/sh
            - -c
            - |-
              TOKEN=\`aws ecr get-login --region BREGION --registry-ids BAWS_ACCOUNT | cut -d' ' -f6)\`
              echo "ENV variables setup done."
              kubectl delete secret -n BNAMESPACE --ignore-not-found regcred
              kubectl create secret -n BNAMESPACE docker-registry regcred --docker-server=https://BAWS_ACCOUNT.dkr.ecr.BREGION.amazonaws.com \
              --docker-username=AWS --docker-password=\${TOKEN} --docker-email=ots@objectway.com
              echo "Secret created by name regcred"
              kubectl patch serviceaccount default -p '{"imagePullSecrets":[{"name":"'regcred'"}]}' -n BNAMESPACE
              echo "All done."
            env:
            - name: AWS_DEFAULT_REGION
              value: BREGION
            - name: AWS_SECRET_ACCESS_KEY
              value: BAWS_SECRET
            - name: AWS_ACCESS_KEY_ID
              value: BAWS_KEY
            - name: ACCOUNT
              value: BAWS_ACCOUNT
            - name: SECRET_NAME
              value: regcred
            - name: REGION
              value: BREGION
            - name: EMAIL
              value: ots@objectway.com
            image: public.ecr.aws/d8v6r0q8/ots-common/aws-kubectl:v1
            imagePullPolicy: IfNotPresent
            name: ecr-cred-helper
            resources: {}
            terminationMessagePath: /dev/termination-log
            terminationMessagePolicy: File
          dnsPolicy: ClusterFirst
          restartPolicy: OnFailure
          schedulerName: default-scheduler
          securityContext: {}
          serviceAccount: sa-ecr-token-helper
          serviceAccountName: sa-ecr-token-helper
          terminationGracePeriodSeconds: 30
  schedule: 0 */6 * * *
  successfulJobsHistoryLimit: 0
  suspend: false
EOF

### Replacing with variables ###

sed -i "s|BREGION|${BREGION}|g" cronjob.yaml
sed -i "s|BNAMESPACE|$BNAMESPACE|g" cronjob.yaml
sed -i "s|BAWS_SECRET|$BAWS_SECRET|g" cronjob.yaml
sed -i "s|BAWS_KEY|$BAWS_KEY|" cronjob.yaml
sed -i "s|BAWS_ACCOUNT|$BAWS_ACCOUNT|g" cronjob.yaml


else
echo 'Answer was NO / exiting...'
exit 1
fi
echo ""
echo "#### cronjob.yaml created ####"
echo "------------------------------"
echo "To not wait 6h to run the job, run the command below to run now:"
echo "kubectl create job --from=cronjob/ecr-cred-helper ecr-cred-helper -n $BNAMESPACE"
echo "------------------------------"
echo "DONE"
echo ""
