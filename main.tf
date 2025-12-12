terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# 1. Resource Group
resource "azurerm_resource_group" "rg" {
  name     = "my-terraform-rg"
  location = "francecentral"
}

# 2. VNet + Subnet
resource "azurerm_virtual_network" "vnet" {
  name                = "my-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "subnet" {
  name                 = "my-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]
}

# 3. Public IP
resource "azurerm_public_ip" "server_publicip" {
  name                = "dhcp-server-publicip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# 4. NSG
resource "azurerm_network_security_group" "server_nsg" {
  name                = "dhcp-server-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_network_security_rule" "ssh_rule" {
  name                        = "SSH_Access"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_network_security_group.server_nsg.resource_group_name
  network_security_group_name = azurerm_network_security_group.server_nsg.name
}

resource "azurerm_network_security_rule" "dhcp_rule" {
  name                        = "DHCP_UDP67"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Udp"
  source_port_range           = "*"
  destination_port_range      = "67"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_network_security_group.server_nsg.resource_group_name
  network_security_group_name = azurerm_network_security_group.server_nsg.name
}

# 5. Server NIC (Static IP)
resource "azurerm_network_interface" "server_nic" {
  name                = "dhcp-server-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.2.10"
    public_ip_address_id          = azurerm_public_ip.server_publicip.id
  }
}

# 5a. Associate NIC with NSG
resource "azurerm_network_interface_security_group_association" "server_nic_nsg" {
  network_interface_id      = azurerm_network_interface.server_nic.id
  network_security_group_id = azurerm_network_security_group.server_nsg.id
}

# 6. DHCP Server VM
resource "azurerm_linux_virtual_machine" "server_vm" {
  name                            = "dhcp-server-vm"
  location                        = azurerm_resource_group.rg.location
  resource_group_name             = azurerm_resource_group.rg.name
  size                            = "Standard_B2S"
  network_interface_ids           = [azurerm_network_interface.server_nic.id]
  disable_password_authentication = false
  admin_username                  = "azureuser"
  admin_password                  = "@Qwerty123"

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  custom_data = base64encode(<<-EOF
    #cloud-config
    runcmd:
      - apt update
      - apt install -y isc-dhcp-server
      - echo 'INTERFACESv4="eth0"' > /etc/default/isc-dhcp-server
      - cat <<EOT > /etc/dhcp/dhcpd.conf
        default-lease-time 600;
        max-lease-time 7200;
        authoritative;
        subnet 10.0.2.0 netmask 255.255.255.0 {
          range 10.0.2.50 10.0.2.150;
          option routers 10.0.2.10;
          option subnet-mask 255.255.255.0;
          option domain-name-servers 8.8.8.8, 1.1.1.1;
        }
        EOT
      - systemctl enable isc-dhcp-server
      - systemctl restart isc-dhcp-server
  EOF
  )
}

# 7. Outputs
output "server_public_ip" {
  value = azurerm_public_ip.server_publicip.ip_address
}

output "server_private_ip" {
  value = azurerm_network_interface.server_nic.private_ip_address
}
