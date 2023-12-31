# Use a lightweight base image
FROM nginx:alpine

# Copy your HTML file to the default Nginx web root directory
COPY index.html /usr/share/nginx/html

# Expose port 80 for web server
EXPOSE 80

# Start Nginx in the foreground when the container starts
CMD ["nginx", "-g", "daemon off;"]
