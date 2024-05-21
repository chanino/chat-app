#!/bin/bash

# Get all subnets
subnets=$(aws ec2 describe-subnets \
    --query "Subnets[*].{ID:SubnetId,VpcId:VpcId}" \
    --region $REGION --profile $PROFILE \
    --output json)

# Parse subnets JSON
for row in $(echo "${subnets}" | jq -r '.[] | @base64'); do
    _jq() {
        echo "${row}" | base64 --decode | jq -r "${1}"
    }

    subnet_id=$(_jq '.ID')
    vpc_id=$(_jq '.VpcId')

    echo "Checking Subnet: ${subnet_id}"

    # Get the route tables for the VPC
    route_tables=$(aws ec2 describe-route-tables \
        --filters "Name=vpc-id,Values=${vpc_id}" \
        --query "RouteTables[*].{RouteTableId:RouteTableId,Associations:Associations,Routes:Routes}" \
        --region $REGION --profile $PROFILE \
        --output json)

    echo "Route tables for VPC: ${route_tables}"

    public=false
    for route_table in $(echo "${route_tables}" | jq -r '.[] | @base64'); do
        _jq_route_table() {
            echo "${route_table}" | base64 --decode | jq -r "${1}"
        }

        route_table_id=$(_jq_route_table '.RouteTableId')
        associations=$(_jq_route_table '.Associations')
        routes=$(_jq_route_table '.Routes')

        echo "Route table ID: ${route_table_id}"
        echo "Associations: ${associations}"
        echo "Routes: ${routes}"

        for association in $(echo "${associations}" | jq -r '.[] | @base64'); do
            _jq_association() {
                echo "${association}" | base64 --decode | jq -r "${1}"
            }

            associated_subnet_id=$(_jq_association '.SubnetId')
            main=$(_jq_association '.Main')

            # Check if this is the main route table or explicitly associated with the subnet
            if [[ "${main}" == "true" || "${associated_subnet_id}" == "${subnet_id}" ]]; then
                echo "Subnet ${subnet_id} is associated with route table ${route_table_id}"

                for route in $(echo "${routes}" | jq -r '.[] | @base64'); do
                    _jq_route() {
                        echo "${route}" | base64 --decode | jq -r "${1}"
                    }

                    destination=$(_jq_route '.DestinationCidrBlock')
                    gateway_id=$(_jq_route '.GatewayId')

                    echo "Route destination: ${destination}, gateway: ${gateway_id}"

                    # Check if the route table has a route to an Internet Gateway (0.0.0.0/0 to igw-xxxxxxxx)
                    if [[ "${destination}" == "0.0.0.0/0" && "${gateway_id}" == igw-* ]]; then
                        public=true
                        break
                    fi
                done
                if [ "${public}" == true ]; then
                    break
                fi
            fi
        done
        if [ "${public}" == true ]; then
            break
        fi
    done

    if [ "${public}" == true ]; then
        echo "Subnet ${subnet_id} is public."
    else
        echo "Subnet ${subnet_id} is private."
    fi
done
