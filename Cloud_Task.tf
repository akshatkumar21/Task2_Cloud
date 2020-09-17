provider "aws" {
	profile ="Akshat"
	region ="ap-south-1"
}

resource "aws_security_group" "task2_sg" {
  name        = "security-1"
  description = "Allow port 80"
  vpc_id      = "vpc-f569719d"

 ingress {
    description = "PORT 80"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

 ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
   
 ingress {
    description= "NFS"
    from_port= 2048
    to_port= 2048
    protocol="tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Webserver_Port"
  }
}

resource "tls_private_key"  "task2key"{
	algorithm= "RSA"
}

resource  "aws_key_pair"   "generated_key"{
	key_name= "task2key"
	public_key= "${tls_private_key.task2key.public_key_openssh}"
	
	depends_on = [
		tls_private_key.task2key
		]
}

resource "local_file"  "store_key_value"{
	content= "${tls_private_key.task2key.private_key_pem}"
 	filename= "task2key.pem"
	
	depends_on = [
		tls_private_key.task2key
	]
}

resource "aws_efs_file_system"  "allow_nfs"{
	creation_token="allow_nfs"
  	tags={
       Name= "allow_nfs"
  	}
}


resource "aws_efs_mount_target"  "efs_mount"{
  file_system_id= "${aws_efs_file_system.allow_nfs.id}"
  subnet_id= "subnet-804445e8"
  security_groups= [aws_security_group.task2_sg.id]
}

resource "aws_instance" "task2_os" {
	ami            ="ami-0447a12f28fddb066"
    instance_type  = "t2.micro"
    availability_zone = "ap-south-1a"
 	key_name = "task2key"
  	security_groups = ["security-1"]

	connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key= "${tls_private_key.task2key.private_key_pem}"
    host     = "${aws_instance.task2_os.public_ip}"
  }

	provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd   git -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd",
    ]
  }

  tags = {
    Name = "Task2_OS"
  }
}

output "myos_ip" {
  value = aws_instance.task2_os.public_ip
}

resource "null_resource" "nulllocal2"  {
	provisioner "local-exec" {
	    command = "echo  aws_instance.task2_os.public_ip > publicip.txt"
  	}
}

resource "null_resource" "nullremote3"  {

	depends_on = [
	    aws_efs_mount_target.efs_mount,
	  ]

 	connection {
	    type     = "ssh"
	    user     = "ec2-user"
	    private_key = "${tls_private_key.task2key.private_key_pem}"
	    host     = "${aws_instance.task2_os.public_ip}"
	}


	provisioner "remote-exec" {
	    inline = [
	      "sudo mkfs.ext4  /dev/xvdh",
	      "sudo mount  /dev/xvdh  /var/www/html",
	      "sudo rm -rf /var/www/html/*",
	      "sudo git clone https://github.com/akshatkumar21/Task2_Cloud.git   /var/www/html/"
	    ]
	 }
}

resource "aws_s3_bucket" "my-s3-akshat-bucket" {   
	bucket = "my-s3-akshat-bucket"
	acl="public-read"
    force_destroy=true

	tags = {     
	      Name = "My_Image_Bucket "   
	} 
} 

resource "aws_s3_bucket_public_access_block" "aws_public_access" {
  bucket = "${aws_s3_bucket.my-s3-akshat-bucket.id}"

  block_public_acls   = false
  block_public_policy = false
}

resource "aws_cloudfront_distribution" "s3_distribution" {   
	origin {     
	domain_name = "${aws_s3_bucket.my-s3-akshat-bucket.bucket_regional_domain_name}"     
        origin_id   = "${aws_s3_bucket.my-s3-akshat-bucket.id}"  
    } 

  	enabled             = true   
  	is_ipv6_enabled     = true   
  	comment             = "S3 bucket"  

    default_cache_behavior {     
	allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]     
	cached_methods   = ["GET", "HEAD"]     
	target_origin_id = "${aws_s3_bucket.my-s3-akshat-bucket.id}" 

    forwarded_values {       
		query_string = false  
          cookies {         
		  	forward = "none"       
          }     
    }  
 
	viewer_protocol_policy = "allow-all"     
	min_ttl                = 0     
	default_ttl            = 3600     
	max_ttl                = 86400   
 }  

   # Cache behavior with precedence 0   
	ordered_cache_behavior {     
		path_pattern     = "/content/immutable/*"     
		allowed_methods  = ["GET", "HEAD", "OPTIONS"]     
		cached_methods   = ["GET", "HEAD", "OPTIONS"]     
		target_origin_id = "${aws_s3_bucket.my-s3-akshat-bucket.id}"  

	    forwarded_values {       
			query_string = false  
	        cookies {         
				forward = "none"       
		    }     
	    }  
	
		min_ttl                = 0     
		default_ttl            = 86400     
		max_ttl                = 31536000 
		compress               = true     
		viewer_protocol_policy = "redirect-to-https"   
    }

 	restrictions {     
		geo_restriction {       
			restriction_type = "none"     
		}   
	}  

	tags = {     
		Environment = "Production"   
	} 

  	viewer_certificate {     
		cloudfront_default_certificate = true   
	}  
  	depends_on = [ aws_s3_bucket.my-s3-akshat-bucket ] 
} 